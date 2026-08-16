import CoreGraphics
import Foundation

struct NormalizedIcon {
    let image: CGImage
    let foregroundFraction: Float
}

enum IconNormalizer {
    private struct Bitmap {
        let width: Int
        let height: Int
        var pixels: [UInt8]

        init?(_ image: CGImage) {
            let imageWidth = image.width
            let imageHeight = image.height
            guard imageWidth > 0, imageHeight > 0 else { return nil }
            var buffer = Array(repeating: UInt8(0), count: imageWidth * imageHeight * 4)
            let didDraw = buffer.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(
                    data: bytes.baseAddress,
                    width: imageWidth,
                    height: imageHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: imageWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
                return true
            }
            guard didDraw else { return nil }
            width = imageWidth
            height = imageHeight
            pixels = buffer
        }

        func rgba(x: Int, y: Int) -> (Int, Int, Int, Int) {
            let index = (y * width + x) * 4
            return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]), Int(pixels[index + 3]))
        }
    }

    static func normalizeTemplate(_ image: CGImage) -> NormalizedIcon? {
        guard let bitmap = Bitmap(image) else { return nil }
        var mask = Array(repeating: false, count: bitmap.width * bitmap.height)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.rgba(x: x, y: y).3 >= 30 {
                mask[y * bitmap.width + x] = true
            }
        }
        return normalized(
            bitmap: bitmap,
            mask: mask,
            regionPixelCount: bitmap.width * bitmap.height,
            retainOnlyLargestComponent: false
        )
    }

    static func normalizeCell(_ image: CGImage) -> NormalizedIcon? {
        normalizeCell(image, kind: nil)
    }

    static func normalizeCell(_ image: CGImage, kind: ItemKind?) -> NormalizedIcon? {
        guard let bitmap = Bitmap(image) else { return nil }
        // 슬롯의 이중 테두리는 바깥 15% 안쪽에 있으므로 아이콘 비교에서 완전히 제외한다.
        let minX = max(0, Int(Double(bitmap.width) * 0.22))
        let maxXFactor = kind == .artifact ? 0.69 : 0.78
        let maxX = min(bitmap.width - 1, Int(Double(bitmap.width) * maxXFactor))
        let minY = max(0, Int(Double(bitmap.height) * 0.22))
        let maxY = min(bitmap.height - 1, Int(Double(bitmap.height) * 0.78))

        var redSamples: [Int] = []
        var greenSamples: [Int] = []
        var blueSamples: [Int] = []
        // 슬롯 바탕이 내부 픽셀의 절반 이상을 차지하므로 전체 내부 중앙값이 가장 안정적이다.
        // 예전의 오른쪽 띠 샘플은 긴 손잡이나 증폭 게이지가 겹치면 아이콘 색을 바탕으로
        // 오인해 전경 마스크가 크게 일그러질 수 있었다.
        for y in minY...maxY {
            for x in minX...maxX {
                let rgba = bitmap.rgba(x: x, y: y)
                redSamples.append(rgba.0)
                greenSamples.append(rgba.1)
                blueSamples.append(rgba.2)
            }
        }
        guard let backgroundRed = median(redSamples),
              let backgroundGreen = median(greenSamples),
              let backgroundBlue = median(blueSamples) else { return nil }

        var mask = Array(repeating: false, count: bitmap.width * bitmap.height)
        let thresholdSquared = 42 * 42
        for y in minY...maxY {
            for x in minX...maxX {
                let relativeX = Double(x - minX) / Double(max(maxX - minX, 1))
                let relativeY = Double(y - minY) / Double(max(maxY - minY, 1))
                // 증폭 수치와 레벨 표시는 화면 좌표계 방향과 무관하게 왼쪽 위/아래 모서리에서 제외한다.
                if relativeX < 0.48 && (relativeY < 0.18 || relativeY > 0.82) { continue }
                // 아티팩트 칸 오른쪽의 증폭 게이지는 아이콘과 겹친다. 오른쪽 위만 제외해 손잡이처럼
                // 오른쪽 아래로 뻗는 실제 아이콘 픽셀은 남긴다.
                if kind == .artifact && relativeX > 0.64 && relativeY < 0.74 { continue }
                let rgba = bitmap.rgba(x: x, y: y)
                guard rgba.3 >= 30 else { continue }
                let red = rgba.0 - backgroundRed
                let green = rgba.1 - backgroundGreen
                let blue = rgba.2 - backgroundBlue
                if red * red + green * green + blue * blue >= thresholdSquared {
                    mask[y * bitmap.width + x] = true
                }
            }
        }
        return normalized(
            bitmap: bitmap,
            mask: mask,
            regionPixelCount: max((maxX - minX + 1) * (maxY - minY + 1), 1),
            retainOnlyLargestComponent: false
        )
    }

    static func slotEdgeScore(_ image: CGImage) -> Float {
        guard let bitmap = Bitmap(image), bitmap.width > 2, bitmap.height > 2 else { return 0 }
        var total = 0
        var comparisons = 0
        for y in 1..<(bitmap.height - 1) {
            for x in 1..<(bitmap.width - 1) {
                let current = bitmap.rgba(x: x, y: y)
                let right = bitmap.rgba(x: x + 1, y: y)
                let down = bitmap.rgba(x: x, y: y + 1)
                total += abs(current.0 - right.0) + abs(current.1 - right.1) + abs(current.2 - right.2)
                total += abs(current.0 - down.0) + abs(current.1 - down.1) + abs(current.2 - down.2)
                comparisons += 6
            }
        }
        return comparisons > 0 ? Float(total) / Float(comparisons) : 0
    }

    static func slotInteriorColor(_ image: CGImage) -> SIMD3<Float>? {
        guard let bitmap = Bitmap(image) else { return nil }
        let minX = Int(Double(bitmap.width) * 0.30)
        let maxX = Int(Double(bitmap.width) * 0.70)
        let minY = Int(Double(bitmap.height) * 0.30)
        let maxY = Int(Double(bitmap.height) * 0.70)
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        var count: Float = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let color = bitmap.rgba(x: x, y: y)
                red += Float(color.0)
                green += Float(color.1)
                blue += Float(color.2)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return SIMD3(red / count, green / count, blue / count)
    }

    static func detectedKind(_ image: CGImage) -> ItemKind? {
        guard normalizeCell(image) != nil, let bitmap = Bitmap(image) else { return nil }
        // 아티팩트의 용량 숫자는 슬롯 가장자리의 위쪽(좌표계에 따라 아래쪽)에 있고,
        // 석판에는 없다. 예전 범위는 중앙 아이콘까지 내려와 밝은 석판을 아티팩트로
        // 오인했으므로 숫자만 들어오는 얇은 모서리 띠를 검사한다.
        let minX = Int(Double(bitmap.width) * 0.05)
        let maxX = Int(Double(bitmap.width) * 0.46)
        let bandMin = Int(Double(bitmap.height) * 0.03)
        let bandMax = Int(Double(bitmap.height) * 0.22)

        func brightNeutralCount(yRange: ClosedRange<Int>) -> Int {
            var count = 0
            for y in yRange {
                for x in minX...maxX {
                    let color = bitmap.rgba(x: x, y: y)
                    let maximum = max(color.0, color.1, color.2)
                    let minimum = min(color.0, color.1, color.2)
                    if maximum >= 165 && maximum - minimum <= 85 { count += 1 }
                }
            }
            return count
        }

        let upper = brightNeutralCount(yRange: bandMin...bandMax)
        let lower = brightNeutralCount(
            yRange: (bitmap.height - bandMax - 1)...(bitmap.height - bandMin - 1)
        )
        return max(upper, lower) >= 9 ? .artifact : .tablet
    }

    private static func normalized(
        bitmap: Bitmap,
        mask: [Bool],
        regionPixelCount: Int,
        retainOnlyLargestComponent: Bool
    ) -> NormalizedIcon? {
        let components = connectedComponents(mask: mask, width: bitmap.width, height: bitmap.height)
        guard let largest = components.max(by: { $0.count < $1.count }), largest.count >= 8 else { return nil }
        let minimumComponentSize = max(3, largest.count / 12)
        let retained = retainOnlyLargestComponent
            ? largest
            : components.filter { $0.count >= minimumComponentSize }.flatMap { $0 }
        let fraction = Float(retained.count) / Float(regionPixelCount)
        guard fraction >= 0.012 else { return nil }

        let xs = retained.map { $0 % bitmap.width }
        let ys = retained.map { $0 / bitmap.width }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let sourceWidth = maxX - minX + 1
        let sourceHeight = maxY - minY + 1
        guard sourceWidth >= 2, sourceHeight >= 2 else { return nil }

        let retainedSet = Set(retained)
        let outputSize = 96
        let padding = 8
        let usable = outputSize - padding * 2
        let scale = min(Double(usable) / Double(sourceWidth), Double(usable) / Double(sourceHeight))
        let drawWidth = max(1, Int(Double(sourceWidth) * scale))
        let drawHeight = max(1, Int(Double(sourceHeight) * scale))
        let offsetX = (outputSize - drawWidth) / 2
        let offsetY = (outputSize - drawHeight) / 2
        var output = Array(repeating: UInt8(0), count: outputSize * outputSize * 4)
        for pixel in 0..<(outputSize * outputSize) {
            output[pixel * 4 + 3] = 255
        }

        for outY in 0..<drawHeight {
            for outX in 0..<drawWidth {
                let sourceX = minX + min(sourceWidth - 1, Int(Double(outX) / scale))
                let sourceY = minY + min(sourceHeight - 1, Int(Double(outY) / scale))
                let sourceIndex = sourceY * bitmap.width + sourceX
                guard retainedSet.contains(sourceIndex) else { continue }
                let sourceRGBA = bitmap.rgba(x: sourceX, y: sourceY)
                let outputIndex = ((offsetY + outY) * outputSize + offsetX + outX) * 4
                output[outputIndex] = UInt8(sourceRGBA.0)
                output[outputIndex + 1] = UInt8(sourceRGBA.1)
                output[outputIndex + 2] = UInt8(sourceRGBA.2)
                output[outputIndex + 3] = 255
            }
        }

        let image = output.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: outputSize,
                height: outputSize,
                bitsPerComponent: 8,
                bytesPerRow: outputSize * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let image else { return nil }
        return NormalizedIcon(image: image, foregroundFraction: fraction)
    }

    private static func connectedComponents(mask: [Bool], width: Int, height: Int) -> [[Int]] {
        var visited = Array(repeating: false, count: mask.count)
        var result: [[Int]] = []
        let directions = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

        for index in mask.indices where mask[index] && !visited[index] {
            visited[index] = true
            var queue = [index]
            var cursor = 0
            var component: [Int] = []
            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                component.append(current)
                let x = current % width
                let y = current / width
                for direction in directions {
                    let nextX = x + direction.0
                    let nextY = y + direction.1
                    guard nextX >= 0, nextY >= 0, nextX < width, nextY < height else { continue }
                    let next = nextY * width + nextX
                    if mask[next] && !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
            result.append(component)
        }
        return result
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
