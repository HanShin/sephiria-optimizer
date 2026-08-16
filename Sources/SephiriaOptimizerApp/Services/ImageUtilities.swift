import AppKit
import CoreGraphics

enum ImageUtilities {
    static func slotGridRect(fromOuterPanel rect: CGRect) -> CGRect {
        // 사용자는 갈색 인벤토리 판의 바깥 테두리를 선택한다. 실제 슬롯은 판 내부에서
        // 왼쪽 3%, 오른쪽 2%, 위 3%, 아래 4%만큼 안쪽에 있다.
        CGRect(
            x: rect.minX + rect.width * 0.03,
            y: rect.minY + rect.height * 0.03,
            width: rect.width * 0.95,
            height: rect.height * 0.93
        )
    }

    static func crop(_ image: CGImage, normalizedRect: CGRect) -> CGImage? {
        let rect = CGRect(
            x: normalizedRect.minX * CGFloat(image.width),
            y: normalizedRect.minY * CGFloat(image.height),
            width: normalizedRect.width * CGFloat(image.width),
            height: normalizedRect.height * CGFloat(image.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width > 1, rect.height > 1 else { return nil }
        return image.cropping(to: rect)
    }

    static func cellImages(from image: CGImage, inventoryRect: CGRect, grid: InventoryGrid) -> [GridPosition: CGImage] {
        guard let inventory = crop(image, normalizedRect: inventoryRect) else { return [:] }
        let cellWidth = CGFloat(inventory.width) / CGFloat(InventoryGrid.columnCount)
        let cellHeight = CGFloat(inventory.height) / CGFloat(grid.rowCount)
        var output: [GridPosition: CGImage] = [:]
        for position in grid.positions {
            let insetX = cellWidth * 0.015
            let insetY = cellHeight * 0.015
            let rect = CGRect(
                x: CGFloat(position.column) * cellWidth + insetX,
                y: CGFloat(position.row) * cellHeight + insetY,
                width: cellWidth - insetX * 2,
                height: cellHeight - insetY * 2
            ).integral
            output[position] = inventory.cropping(to: rect)
        }
        return output
    }

    static func cgImage(from data: Data) -> CGImage? {
        guard let image = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func rotated(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }
        let swapsDimensions = turns % 2 == 1
        let width = swapsDimensions ? image.height : image.width
        let height = swapsDimensions ? image.width : image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: CGFloat(turns) * .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }
}
