import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct RecognitionMatch: Sendable {
    let item: CatalogItem
    let rotation: Int
    let distance: Float
    let confidence: Float
}

enum TemplateMatcherError: LocalizedError {
    case noTemplates
    case cannotCreateFeaturePrint

    var errorDescription: String? {
        switch self {
        case .noTemplates: "인식 템플릿을 준비하지 못했습니다. 인터넷 연결을 확인한 뒤 템플릿 동기화를 다시 실행해 주세요."
        case .cannotCreateFeaturePrint: "아이템 이미지의 특징을 계산하지 못했습니다."
        }
    }
}

@MainActor
final class TemplateMatcher {
    nonisolated private static let maximumLearnedSamples = 5

    private struct ImageDescriptor: Sendable {
        let values: [Float]

        func distance(to other: ImageDescriptor) -> Float {
            guard values.count == other.values.count, !values.isEmpty else { return .greatestFiniteMagnitude }
            var total: Float = 0
            for index in values.indices {
                let difference = values[index] - other.values[index]
                total += difference * difference
            }
            return sqrt(total / Float(values.count)) * 100
        }
    }

    private struct Raster: Sendable {
        let size: Int
        let rgba: [UInt8]
    }

    private struct Template {
        let item: CatalogItem
        let rotation: Int
        let descriptor: ImageDescriptor
        let raster: Raster
        let normalizedImage: CGImage
        let isLearned: Bool
    }

    private var templates: [Template] = []
    private var featurePrintCache: [String: VNFeaturePrintObservation] = [:]
    var isReady: Bool { !templates.isEmpty }
    var templateCount: Int { templates.count }

    func prepare(
        items: [CatalogItem],
        includeLearned: Bool = true,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws {
        templates.removeAll(keepingCapacity: true)
        featurePrintCache.removeAll(keepingCapacity: true)
        let total = items.count
        var completed = 0

        for batchStart in stride(from: 0, to: items.count, by: 12) {
            let batch = Array(items[batchStart..<min(batchStart + 12, items.count)])
            let images = await withTaskGroup(of: (CatalogItem, Data?).self) { group in
                for item in batch {
                    group.addTask { (item, await Self.cachedImageData(for: item)) }
                }
                var result: [(CatalogItem, Data?)] = []
                for await value in group { result.append(value) }
                return result
            }

            for (item, data) in images {
                defer {
                    completed += 1
                    progress(completed, total)
                }
                guard let data, let image = ImageUtilities.cgImage(from: data) else { continue }
                let rotations: [Int]
                if case .tablet(let tablet) = item, tablet.isRotatable {
                    rotations = [0, 1, 2, 3]
                } else {
                    rotations = [0]
                }
                for rotation in rotations {
                    guard let rotated = ImageUtilities.rotated(image, quarterTurns: rotation),
                          let normalized = IconNormalizer.normalizeTemplate(rotated),
                          let descriptor = Self.descriptor(for: normalized.image),
                          let raster = Self.raster(for: rotated, preservingAlpha: true) else { continue }
                    templates.append(
                        Template(
                            item: item,
                            rotation: rotation,
                            descriptor: descriptor,
                            raster: raster,
                            normalizedImage: normalized.image,
                            isLearned: false
                        )
                    )
                }
            }
        }

        if includeLearned { loadLearnedTemplates(items: items) }
        guard !templates.isEmpty else { throw TemplateMatcherError.noTemplates }
    }

    func clearLearnedTemplates() {
        templates.removeAll { $0.isLearned }
        guard let directory = Self.learnedDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    func learn(item: CatalogItem, rotation: Int, from cell: CGImage, persist: Bool = true) -> Bool {
        guard let normalized = IconNormalizer.normalizeCell(cell, kind: item.kind),
              let descriptor = Self.descriptor(for: normalized.image) else { return false }
        let normalizedRotation = ((rotation % 4) + 4) % 4

        let matchingLearned = templates.indices.filter {
            templates[$0].isLearned
                && templates[$0].item.id == item.id
                && templates[$0].rotation == normalizedRotation
        }
        if matchingLearned.contains(where: { templates[$0].descriptor.distance(to: descriptor) < 0.35 }) {
            return true
        }
        if matchingLearned.count >= Self.maximumLearnedSamples, let oldestIndex = matchingLearned.first {
            templates.remove(at: oldestIndex)
        }
        templates.append(
            Template(
                item: item,
                rotation: normalizedRotation,
                descriptor: descriptor,
                raster: Self.raster(for: cell, preservingAlpha: false) ?? Raster(size: 40, rgba: []),
                normalizedImage: normalized.image,
                isLearned: true
            )
        )
        guard persist, let fileURL = Self.nextLearnedFileURL(for: item, rotation: normalizedRotation) else { return true }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return false }
        CGImageDestinationAddImage(destination, normalized.image, nil)
        return CGImageDestinationFinalize(destination)
    }

    func match(_ image: CGImage, acceptanceDistance: Float = 38) throws -> RecognitionMatch? {
        let matches = try topMatches(image, limit: 2)
        guard let best = matches.first, best.distance <= acceptanceDistance else { return nil }
        return best
    }

    func topMatches(_ image: CGImage, limit: Int = 5) throws -> [RecognitionMatch] {
        guard !templates.isEmpty else { throw TemplateMatcherError.noTemplates }
        guard let detectedKind = IconNormalizer.detectedKind(image) else { return [] }
        guard let artifactIcon = IconNormalizer.normalizeCell(image, kind: .artifact),
              let artifactTarget = Self.descriptor(for: artifactIcon.image),
              let tabletIcon = IconNormalizer.normalizeCell(image, kind: .tablet),
              let tabletTarget = Self.descriptor(for: tabletIcon.image),
              let targetRaster = Self.raster(for: image, preservingAlpha: false) else {
            throw TemplateMatcherError.cannotCreateFeaturePrint
        }
        var bestByItemAndRotation: [String: (Template, Float)] = [:]
        bestByItemAndRotation.reserveCapacity(templates.count)

        for template in templates where template.item.kind == detectedKind {
            let target = template.item.kind == .artifact ? artifactTarget : tabletTarget
            let descriptorDistance = target.distance(to: template.descriptor)
            let distance: Float
            if template.isLearned {
                // A learned screen sample should be genuinely close. This prevents an old,
                // wrongly corrected sample from dominating every later capture forever.
                distance = descriptorDistance <= 8 ? descriptorDistance : 100
            } else if template.item.kind == .artifact {
                let shapeDistance = Self.shapeDistance(template: template.raster, target: targetRaster)
                distance = shapeDistance
            } else {
                distance = descriptorDistance
            }
            let key = "\(template.item.id)#\(template.rotation)"
            if let current = bestByItemAndRotation[key] {
                if distance < current.1 { bestByItemAndRotation[key] = (template, distance) }
            } else {
                bestByItemAndRotation[key] = (template, distance)
            }
        }
        var distances = Array(bestByItemAndRotation.values)
        distances.sort { $0.1 < $1.1 }
        if detectedKind == .artifact,
           let targetFeaturePrint = Self.featurePrint(for: artifactIcon.image) {
            let rerankCount = min(32, distances.count)
            for index in 0..<rerankCount where !distances[index].0.isLearned {
                let template = distances[index].0
                let key = "\(template.item.id)#\(template.rotation)"
                let templateFeaturePrint: VNFeaturePrintObservation?
                if let cached = featurePrintCache[key] {
                    templateFeaturePrint = cached
                } else {
                    templateFeaturePrint = Self.featurePrint(for: template.normalizedImage)
                    if let templateFeaturePrint { featurePrintCache[key] = templateFeaturePrint }
                }
                guard let templateFeaturePrint else { continue }
                var visionDistance: Float = 0
                guard (try? targetFeaturePrint.computeDistance(&visionDistance, to: templateFeaturePrint)) != nil else {
                    continue
                }
                distances[index].1 = distances[index].1 * 0.25 + visionDistance * 0.75
            }
            distances.sort { $0.1 < $1.1 }
        }
        let secondDistance = distances.dropFirst().first?.1 ?? distances.first?.1 ?? 1
        return distances.prefix(max(1, limit)).enumerated().map { index, entry in
            let margin = index == 0 ? max(0, secondDistance - entry.1) : 0
            let confidence = max(0, min(1, margin / max(secondDistance, 0.001) * 5))
            return RecognitionMatch(
                item: entry.0.item,
                rotation: entry.0.rotation,
                distance: entry.1,
                confidence: confidence
            )
        }
    }

    private static func descriptor(for image: CGImage) -> ImageDescriptor? {
        let size = 32
        var pixels = Array(repeating: UInt8(0), count: size * size * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard didDraw else { return nil }
        var values: [Float] = []
        values.reserveCapacity(size * size * 3)
        for pixel in 0..<(size * size) {
            let index = pixel * 4
            values.append(Float(pixels[index]) / 255)
            values.append(Float(pixels[index + 1]) / 255)
            values.append(Float(pixels[index + 2]) / 255)
        }
        return ImageDescriptor(values: values)
    }

    private static func featurePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first as? VNFeaturePrintObservation
    }

    private static func raster(for image: CGImage, preservingAlpha: Bool) -> Raster? {
        let size = 40
        var pixels = Array(repeating: UInt8(0), count: size * size * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: preservingAlpha
                    ? CGImageAlphaInfo.premultipliedLast.rawValue
                    : CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard didDraw else { return nil }
        return Raster(size: size, rgba: pixels)
    }

    private static func shapeDistance(template: Raster, target: Raster) -> Float {
        guard template.size == target.size, template.rgba.count == target.rgba.count else {
            return 100
        }
        let size = target.size
        var redSamples: [UInt8] = []
        var greenSamples: [UInt8] = []
        var blueSamples: [UInt8] = []
        for y in Int(Double(size) * 0.18)..<Int(Double(size) * 0.82) {
            for x in Int(Double(size) * 0.18)..<Int(Double(size) * 0.82) {
                let index = (y * size + x) * 4
                redSamples.append(target.rgba[index])
                greenSamples.append(target.rgba[index + 1])
                blueSamples.append(target.rgba[index + 2])
            }
        }
        redSamples.sort()
        greenSamples.sort()
        blueSamples.sort()
        guard !redSamples.isEmpty else { return 100 }
        let background = (
            Float(redSamples[redSamples.count / 2]),
            Float(greenSamples[greenSamples.count / 2]),
            Float(blueSamples[blueSamples.count / 2])
        )
        let contrastThresholdSquared: Float = 22 * 22
        var best: Float = 100

        for offsetY in -1...1 {
            for offsetX in -1...1 {
                    var templateCount = 0
                    var targetCount = 0
                    var intersection = 0
                    var colorError: Float = 0
                    var templateHistogram = Array(repeating: Float(0), count: 8)
                    var targetHistogram = Array(repeating: Float(0), count: 8)
                    for y in 0..<size {
                        for x in 0..<size {
                        let normalizedX = Double(x) / Double(size)
                        let normalizedY = Double(y) / Double(size)
                        let cleanHead = normalizedX >= 0.16 && normalizedX <= 0.67
                            && normalizedY >= 0.28 && normalizedY <= 0.74
                        let cleanHandle = normalizedX >= 0.42 && normalizedX <= 0.78
                            && normalizedY >= 0.58 && normalizedY <= 0.82
                        guard cleanHead || cleanHandle else { continue }
                        let targetX = x + offsetX
                        let targetY = y + offsetY
                        guard targetX >= 0, targetY >= 0, targetX < size, targetY < size else { continue }
                        let templateIndex = (y * size + x) * 4
                        let targetIndex = (targetY * size + targetX) * 4
                        let alpha = Float(template.rgba[templateIndex + 3]) / 255
                        let templateRed = alpha > 0 ? min(255, Float(template.rgba[templateIndex]) / alpha) : 0
                        let templateGreen = alpha > 0 ? min(255, Float(template.rgba[templateIndex + 1]) / alpha) : 0
                        let templateBlue = alpha > 0 ? min(255, Float(template.rgba[templateIndex + 2]) / alpha) : 0
                        let targetRed = Float(target.rgba[targetIndex])
                        let targetGreen = Float(target.rgba[targetIndex + 1])
                        let targetBlue = Float(target.rgba[targetIndex + 2])
                        let templateContrast = squaredDistance(
                            templateRed, templateGreen, templateBlue,
                            background.0, background.1, background.2
                        )
                        let targetContrast = squaredDistance(
                            targetRed, targetGreen, targetBlue,
                            background.0, background.1, background.2
                        )
                        let templateForeground = alpha >= 0.30 && templateContrast >= contrastThresholdSquared
                        let targetForeground = targetContrast >= contrastThresholdSquared
                        if templateForeground {
                            templateCount += 1
                            templateHistogram[colorBin(templateRed, templateGreen, templateBlue)] += 1
                        }
                        if targetForeground {
                            targetCount += 1
                            targetHistogram[colorBin(targetRed, targetGreen, targetBlue)] += 1
                        }
                        if templateForeground && targetForeground {
                            intersection += 1
                            colorError += sqrt(squaredDistance(
                                templateRed, templateGreen, templateBlue,
                                targetRed, targetGreen, targetBlue
                            ) / 3) / 255
                        }
                    }
                }
                guard templateCount > 4, targetCount > 4, intersection > 0 else { continue }
                let dice = Float(intersection * 2) / Float(templateCount + targetCount)
                let averageColorError = colorError / Float(intersection)
                var histogramDistance: Float = 0
                for index in templateHistogram.indices {
                    histogramDistance += abs(
                        templateHistogram[index] / Float(templateCount)
                            - targetHistogram[index] / Float(targetCount)
                    )
                }
                histogramDistance /= 2
                best = min(best, (1 - dice) * 55 + histogramDistance * 35 + averageColorError * 10)
            }
        }
        return best
    }

    private static func squaredDistance(
        _ red1: Float, _ green1: Float, _ blue1: Float,
        _ red2: Float, _ green2: Float, _ blue2: Float
    ) -> Float {
        let red = red1 - red2
        let green = green1 - green2
        let blue = blue1 - blue2
        return red * red + green * green + blue * blue
    }

    private static func colorBin(_ red: Float, _ green: Float, _ blue: Float) -> Int {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        if maximum < 72 { return 0 }
        if maximum - minimum < 28 { return 1 }
        if blue > red * 1.15 && blue > green * 1.08 { return 2 }
        if green > red * 1.10 && green > blue * 1.05 { return 3 }
        if red > green * 1.10 && red > blue * 1.10 { return 4 }
        if blue + green > red * 2.25 { return 5 }
        if red + green > blue * 2.25 { return 6 }
        return 7
    }

    private func loadLearnedTemplates(items: [CatalogItem]) {
        for item in items {
            let rotations = item.kind == .tablet ? [0, 1, 2, 3] : [0]
            for rotation in rotations {
                for fileURL in Self.learnedFileURLs(for: item, rotation: rotation).prefix(Self.maximumLearnedSamples) {
                    guard let data = try? Data(contentsOf: fileURL),
                          let image = ImageUtilities.cgImage(from: data),
                          let descriptor = Self.descriptor(for: image),
                          let raster = Self.raster(for: image, preservingAlpha: false) else { continue }
                    templates.append(
                        Template(
                            item: item,
                            rotation: rotation,
                            descriptor: descriptor,
                            raster: raster,
                            normalizedImage: image,
                            isLearned: true
                        )
                    )
                }
            }
        }
    }

    nonisolated private static func learnedDirectoryAndName(for item: CatalogItem) -> (URL, String)? {
        guard let directory = learnedDirectory else { return nil }
        let safeName = item.id
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return (
            directory,
            safeName
        )
    }

    nonisolated private static var learnedDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SephiriaOptimizer/Learned", isDirectory: true)
    }

    nonisolated private static func learnedFileURLs(for item: CatalogItem, rotation: Int) -> [URL] {
        guard let (directory, safeName) = learnedDirectoryAndName(for: item) else { return [] }
        let fileManager = FileManager.default
        let legacy = directory.appendingPathComponent("\(safeName)__r\(rotation).png")
        let samples = (0..<maximumLearnedSamples).map {
            directory.appendingPathComponent("\(safeName)__r\(rotation)__s\($0).png")
        }.filter { fileManager.fileExists(atPath: $0.path) }
        if !samples.isEmpty { return samples }
        return fileManager.fileExists(atPath: legacy.path) ? [legacy] : []
    }

    nonisolated private static func nextLearnedFileURL(for item: CatalogItem, rotation: Int) -> URL? {
        guard let (directory, safeName) = learnedDirectoryAndName(for: item) else { return nil }
        let fileManager = FileManager.default
        let samples = (0..<maximumLearnedSamples).map {
            directory.appendingPathComponent("\(safeName)__r\(rotation)__s\($0).png")
        }
        if let empty = samples.first(where: { !fileManager.fileExists(atPath: $0.path) }) { return empty }
        return samples.min {
            let left = (try? fileManager.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date) ?? .distantPast
            let right = (try? fileManager.attributesOfItem(atPath: $1.path)[.modificationDate] as? Date) ?? .distantPast
            return left < right
        }
    }

    nonisolated private static func cachedImageData(for item: CatalogItem) async -> Data? {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("SephiriaOptimizer/Templates", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = item.id.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        let fileURL = directory.appendingPathComponent(safeName)

        if let cached = try? Data(contentsOf: fileURL), !cached.isEmpty { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: item.imageURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            try? data.write(to: fileURL, options: .atomic)
            return data
        } catch {
            return nil
        }
    }
}
