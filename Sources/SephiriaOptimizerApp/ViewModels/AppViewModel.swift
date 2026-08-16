import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let calibrationVersion = 2

    @Published var status = "Sephiria에서 인벤토리를 연 뒤 F8을 누르세요."
    @Published var isBusy = false
    @Published var slotCount: Int {
        didSet {
            UserDefaults.standard.set(slotCount, forKey: "slotCount")
            if !isDetectingSlotCount, let capturedCGImage, hasCalibration {
                Task { await recognizeAndOptimize(capturedCGImage) }
            }
        }
    }
    @Published var capturedImage: NSImage?
    @Published var recognizedLayout: InventoryLayout?
    @Published var result: OptimizationResult?
    @Published var showCalibration = false
    @Published var calibrationRect = CGRect(x: 0.2, y: 0.15, width: 0.6, height: 0.7)
    @Published var templateProgress = ""
    @Published var selectedPosition: GridPosition?
    @Published var recognitionSuggestions: [GridPosition: [CatalogItem]] = [:]
    @Published var recognitionSuggestedRotations: [GridPosition: [String: Int]] = [:]
    @Published var cellPreviews: [GridPosition: NSImage] = [:]
    @Published var unresolvedPositions: Set<GridPosition> = []
    @Published var detectedItemCount = 0
    @Published var keepWindowOnTop = true {
        didSet { updateWindowLevel() }
    }

    let catalog: [CatalogItem]
    private let captureService = ScreenCaptureService()
    private let matcher = TemplateMatcher()
    private let hotKey = HotKeyManager()
    private var capturedCGImage: CGImage?
    private var lastOccupiedCells: [GridPosition: CGImage] = [:]
    private(set) var hasCalibration: Bool
    private var isDetectingSlotCount = false

    init() {
        catalog = (try? CatalogService.allItems()) ?? TabletCatalog.all.map(CatalogItem.tablet)
        let storedSlots = UserDefaults.standard.integer(forKey: "slotCount")
        slotCount = storedSlots == 0 ? 34 : min(max(storedSlots, 18), 60)
        hasCalibration = UserDefaults.standard.bool(forKey: "hasCalibration")
            && UserDefaults.standard.integer(forKey: "calibrationVersion") >= Self.calibrationVersion
        if hasCalibration,
           let stored = UserDefaults.standard.dictionary(forKey: "calibrationRect"),
           let x = stored["x"] as? Double,
           let y = stored["y"] as? Double,
           let width = stored["width"] as? Double,
           let height = stored["height"] as? Double {
            calibrationRect = CGRect(x: x, y: y, width: width, height: height)
        }
        hotKey.onPressed = { [weak self] in self?.captureFromGame() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            updateWindowLevel()
        }
    }

    func captureFromGame() {
        guard !isBusy else { return }
        isBusy = true
        status = "Sephiria 창을 캡처하는 중…"
        Task {
            do {
                let image = try await captureService.captureGameWindow()
                capturedCGImage = image
                capturedImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                if hasCalibration {
                    await recognizeAndOptimize(image)
                } else {
                    isBusy = false
                    status = "인벤토리 6열 격자 전체를 드래그해서 지정해 주세요."
                    showCalibration = true
                }
            } catch {
                isBusy = false
                status = error.localizedDescription
            }
        }
    }

    func recalibrate() {
        guard capturedImage != nil else {
            status = "먼저 게임 창을 캡처해 주세요."
            return
        }
        showCalibration = true
    }

    func applyCalibration(_ rect: CGRect) {
        let clamped = CGRect(
            x: max(0, min(rect.minX, 1)),
            y: max(0, min(rect.minY, 1)),
            width: max(0.02, min(rect.width, 1 - rect.minX)),
            height: max(0.02, min(rect.height, 1 - rect.minY))
        )
        calibrationRect = clamped
        hasCalibration = true
        UserDefaults.standard.set(true, forKey: "hasCalibration")
        UserDefaults.standard.set(Self.calibrationVersion, forKey: "calibrationVersion")
        UserDefaults.standard.set(
            ["x": clamped.minX, "y": clamped.minY, "width": clamped.width, "height": clamped.height],
            forKey: "calibrationRect"
        )
        showCalibration = false
        if let capturedCGImage { Task { await recognizeAndOptimize(capturedCGImage) } }
    }

    func recognizeAndOptimize(_ image: CGImage? = nil) async {
        guard let image = image ?? capturedCGImage else { return }
        isBusy = true
        do {
            if !matcher.isReady {
                status = "처음 한 번만 아이템 인식 템플릿을 준비합니다…"
                try await matcher.prepare(items: catalog) { [weak self] completed, total in
                    self?.templateProgress = "템플릿 \(completed)/\(total)"
                }
            }

            status = "인벤토리 아이템을 인식하는 중…"
            // 보정 v2부터는 사용자가 슬롯 격자 자체를 지정하므로 추가 여백을 자르지 않는다.
            let slotGridRect = calibrationRect
            if let detectedCount = GridDetector.detectSlotCount(in: image, inventoryRect: slotGridRect) {
                // 인벤토리는 해금되면 줄어들지 않는다. 같은 행 안에서 20→19처럼 한 칸만
                // 감소한 값은 마지막 슬롯 테두리를 놓친 일시적 감지 오류이므로 유지한다.
                let sameRowCount = InventoryGrid(slotCount: detectedCount).rowCount
                    == InventoryGrid(slotCount: slotCount).rowCount
                let stableDetectedCount = sameRowCount ? max(slotCount, detectedCount) : detectedCount
                if stableDetectedCount != slotCount {
                isDetectingSlotCount = true
                slotCount = stableDetectedCount
                isDetectingSlotCount = false
                status = "인벤토리를 \(stableDetectedCount)칸으로 자동 감지했습니다. 아이템을 인식하는 중…"
                }
            }
            let grid = InventoryGrid(slotCount: slotCount)
            let cells = ImageUtilities.cellImages(from: image, inventoryRect: slotGridRect, grid: grid)
            var pieces: [GridPosition: InventoryPiece] = [:]
            var occupiedCells: [GridPosition: CGImage] = [:]
            var suggestions: [GridPosition: [CatalogItem]] = [:]
            var suggestedRotations: [GridPosition: [String: Int]] = [:]
            var unresolved = Set<GridPosition>()
            for position in grid.positions {
                guard let cell = cells[position] else { continue }
                let matches = try matcher.topMatches(cell, limit: 24)
                guard let match = matches.first else { continue }
                occupiedCells[position] = cell
                var seen = Set<String>()
                suggestions[position] = matches.compactMap { candidate in
                    guard seen.insert(candidate.item.id).inserted else { return nil }
                    return candidate.item
                }
                var rotations: [String: Int] = [:]
                for candidate in matches where rotations[candidate.item.id] == nil {
                    rotations[candidate.item.id] = candidate.rotation
                }
                suggestedRotations[position] = rotations
                guard match.distance <= 38, match.confidence >= 0.45 else {
                    unresolved.insert(position)
                    continue
                }
                pieces[position] = InventoryPiece(
                    item: match.item,
                    rotation: match.rotation,
                    recognitionConfidence: match.confidence
                )
            }
            lastOccupiedCells = occupiedCells
            cellPreviews = occupiedCells.mapValues {
                NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height))
            }
            recognitionSuggestions = suggestions
            recognitionSuggestedRotations = suggestedRotations
            unresolvedPositions = unresolved
            detectedItemCount = occupiedCells.count
            let layout = InventoryLayout(grid: grid, pieces: pieces)
            recognizedLayout = layout
            status = "\(pieces.count)개 아이템을 인식했습니다. 배치를 계산하는 중…"
            await optimize(layout)
        } catch {
            isBusy = false
            status = error.localizedDescription
        }
    }

    func optimizeCurrent() {
        guard let layout = recognizedLayout else {
            status = "먼저 인벤토리를 캡처하거나 칸을 직접 입력해 주세요."
            return
        }
        Task { await optimize(layout) }
    }

    func setItem(_ item: CatalogItem?, at position: GridPosition) {
        guard var layout = recognizedLayout else {
            recognizedLayout = InventoryLayout(grid: InventoryGrid(slotCount: slotCount))
            setItem(item, at: position)
            return
        }
        if let item {
            let rotation = recognitionSuggestedRotations[position]?[item.id] ?? 0
            layout.pieces[position] = InventoryPiece(item: item, rotation: rotation, recognitionConfidence: 1)
            if let cell = lastOccupiedCells[position] {
                _ = matcher.learn(item: item, rotation: rotation, from: cell)
            }
        } else {
            layout.pieces.removeValue(forKey: position)
        }
        unresolvedPositions.remove(position)
        recognizedLayout = layout
        selectedPosition = nil
        Task { await optimize(layout) }
    }

    func rotatePiece(at position: GridPosition) {
        guard var layout = recognizedLayout, var piece = layout.pieces[position], case .tablet(let tablet) = piece.item,
              tablet.isRotatable else { return }
        piece.rotation = (piece.rotation + 1) % 4
        layout.pieces[position] = piece
        recognizedLayout = layout
        Task { await optimize(layout) }
    }

    func resetRecognitionLearning() {
        matcher.clearLearnedTemplates()
        status = "저장된 인식 학습을 초기화했습니다. 현재 화면을 다시 인식합니다…"
        if let capturedCGImage {
            Task { await recognizeAndOptimize(capturedCGImage) }
        }
    }

    private func optimize(_ layout: InventoryLayout) async {
        isBusy = true
        let optimizer = InventoryOptimizer()
        let optimized = await Task.detached(priority: .userInitiated) {
            optimizer.optimize(layout)
        }.value
        result = optimized
        isBusy = false
        templateProgress = ""
        let overflowText = optimized.after.hasNoOverflow ? "초과 0" : "초과 \(optimized.after.overflowAmount)"
        let uncertainCount = unresolvedPositions.count
        let uncertaintyText = uncertainCount > 0 ? " · 확인 필요 \(uncertainCount)칸" : ""
        let totalDetected = max(detectedItemCount, layout.pieces.count + unresolvedPositions.count)
        let recognitionText = totalDetected > 0 ? " · 아이템 \(layout.pieces.count)/\(totalDetected)개 확정" : ""
        status = "완료: 유효 증폭 \(optimized.after.totalUsefulAmplification), \(overflowText)\(recognitionText)\(uncertaintyText)"
    }

    private func updateWindowLevel() {
        for window in NSApplication.shared.windows {
            window.level = keepWindowOnTop ? .floating : .normal
            window.collectionBehavior.insert(.fullScreenAuxiliary)
        }
    }
}
