import CoreGraphics
import Foundation

enum GridDetector {
    static func detectSlotCount(in image: CGImage, inventoryRect: CGRect) -> Int? {
        guard let inventory = ImageUtilities.crop(image, normalizedRect: inventoryRect), inventory.width > 0 else { return nil }
        let estimatedRows = min(
            10,
            max(3, Int(round(Double(inventory.height) / Double(inventory.width) * Double(InventoryGrid.columnCount))))
        )
        let fullCount = estimatedRows * InventoryGrid.columnCount
        guard fullCount >= InventoryGrid.minimumSlotCount, fullCount <= InventoryGrid.maximumSlotCount else { return nil }
        let candidateGrid = InventoryGrid(slotCount: fullCount)
        let cells = ImageUtilities.cellImages(from: image, inventoryRect: inventoryRect, grid: candidateGrid)
        let fullRows = candidateGrid.positions.filter { $0.row < estimatedRows - 1 }
        let baselineScores = fullRows.compactMap { cells[$0] }.map(IconNormalizer.slotEdgeScore).sorted()
        guard !baselineScores.isEmpty else { return nil }
        let baseline = baselineScores[baselineScores.count / 2]
        // 고해상도 캡처에서는 같은 테두리의 픽셀 차이가 더 많은 픽셀에 분산되어
        // 절대 점수가 낮아진다. 고정 0.8 하한은 Retina 캡처에서 마지막 슬롯을
        // 빈 영역으로 오인해 20칸을 19칸으로 줄였으므로 행 내부 상대값을 사용한다.
        let threshold = max(0.12, baseline * 0.34)

        var lastRowCount = 0
        for column in 0..<InventoryGrid.columnCount {
            let position = GridPosition(row: estimatedRows - 1, column: column)
            guard let cell = cells[position], IconNormalizer.slotEdgeScore(cell) >= threshold else { break }
            lastRowCount += 1
        }
        guard lastRowCount > 0 else { return nil }
        return (estimatedRows - 1) * InventoryGrid.columnCount + lastRowCount
    }
}
