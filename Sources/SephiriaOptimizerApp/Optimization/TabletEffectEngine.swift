import Foundation

struct TabletEffectMap: Hashable, Sendable {
    var bonuses: [GridPosition: Int]
    var ignoredConditions: Set<GridPosition>
}

enum TabletEffectEngine {
    private struct Offset {
        let dx: Int
        let dy: Int
        let value: Int
        let ignoresCondition: Bool

        init(_ dx: Int, _ dy: Int, _ value: Int = 1, ignore: Bool = false) {
            self.dx = dx
            self.dy = dy
            self.value = value
            self.ignoresCondition = ignore
        }
    }

    static func effects(for layout: InventoryLayout) -> TabletEffectMap {
        var map = TabletEffectMap(
            bonuses: Dictionary(uniqueKeysWithValues: layout.grid.positions.map { ($0, 0) }),
            ignoredConditions: []
        )

        for (position, piece) in layout.pieces {
            guard case .tablet(let tablet) = piece.item else { continue }
            apply(tablet.id, at: position, rotation: piece.rotation, grid: layout.grid, map: &map)
        }
        return map
    }

    private static func apply(
        _ id: String,
        at origin: GridPosition,
        rotation: Int,
        grid: InventoryGrid,
        map: inout TabletEffectMap
    ) {
        switch id {
        case "approximation": add([.init(0, -1), .init(1, 0)], origin, rotation, grid, &map)
        case "dry": add([.init(0, -1), .init(0, 1)], origin, 0, grid, &map)
        case "chivalry": add([.init(-1, -2)], origin, rotation, grid, &map)
        case "advent": add([.init(0, -1), .init(0, -2), .init(0, 1, -1), .init(0, 2, -1)], origin, rotation, grid, &map)
        case "linear":
            if origin.row == grid.rowCount - 1 {
                add([.init(-1, 0), .init(1, 0)], origin, 0, grid, &map)
            }
        case "sight": add([.init(-1, -1), .init(1, 1, -1)], origin, rotation, grid, &map)
        case "handshake": add([.init(0, -1), .init(0, 1)], origin, rotation, grid, &map)
        case "fate": add([.init(0, 1)], origin, 0, grid, &map)
        case "wit": add([.init(-1, -1)], origin, rotation, grid, &map)
        case "exploitation": add([.init(0, -1), .init(0, 1, -1)], origin, rotation, grid, &map)
        case "unity": add([.init(1, 0), .init(0, 1), .init(0, -1, -1), .init(-1, 0, -1)], origin, rotation, grid, &map)
        case "cheer": add([.init(0, -1)], origin, 0, grid, &map)
        case "hope": add([.init(1, 0)], origin, rotation, grid, &map)
        case "compete": add([.init(0, 1, 3), .init(0, -1, -1), .init(-1, -1, -1)], origin, rotation, grid, &map)
        case "beating": add([.init(0, -2, 2)], origin, rotation, grid, &map)
        case "home_town": add([.init(1, 0, 0, ignore: true)], origin, rotation, grid, &map)
        case "past": add([.init(-1, -1), .init(0, -1), .init(1, -1), .init(1, 0)], origin, rotation, grid, &map)
        case "future": add([.init(-1, -1), .init(0, -1), .init(1, -1), .init(-1, 0)], origin, rotation, grid, &map)
        case "distribution": add([.init(0, -1), .init(-1, 0), .init(1, 0), .init(0, 1)], origin, 0, grid, &map)
        case "triceps": add([.init(0, -1), .init(-1, 0), .init(1, 0)], origin, 0, grid, &map)
        case "harvesting": add([.init(0, 1, 2), .init(0, -1, 2)], origin, rotation, grid, &map)
        case "binary_star": add([.init(0, 2, 2), .init(0, -2, 2)], origin, rotation, grid, &map)
        case "nurture": add([.init(-1, -1), .init(0, -1), .init(1, -1), .init(0, 1, -1), .init(0, 2, -1)], origin, rotation, grid, &map)
        case "yearning": add([.init(0, -1, 2)], origin, 0, grid, &map)
        case "agglutination":
            for position in grid.positions where position != origin {
                if rotation % 2 == 1, position.column == origin.column { map.bonuses[position, default: 0] -= 1 }
                if rotation % 2 == 0, position.row == origin.row { map.bonuses[position, default: 0] -= 1 }
            }
            add([.init(0, -1, 3)], origin, rotation, grid, &map)
        case "entrance": add([.init(0, -1, 2), .init(-1, -1), .init(1, -1)], origin, 0, grid, &map)
        case "joke": add([.init(0, -1), .init(1, -1), .init(-1, -1), .init(-1, 0, -1), .init(1, 0, -1)], origin, rotation, grid, &map)
        case "load": add([.init(0, -1), .init(-1, -1), .init(0, -2), .init(-1, -2)], origin, rotation, grid, &map)
        case "transition":
            let rowValue = rotation % 2 == 1 ? -1 : 1
            let columnValue = -rowValue
            for position in grid.positions where position != origin {
                if position.row == origin.row { map.bonuses[position, default: 0] += rowValue }
                if position.column == origin.column { map.bonuses[position, default: 0] += columnValue }
            }
        case "advance": add([.init(0, -1), .init(0, -2), .init(0, -3)], origin, rotation, grid, &map)
        case "justice":
            let rowSlots = grid.positions.filter { $0.row == origin.row }
            if origin.column == rowSlots.first?.column || origin.column == rowSlots.last?.column {
                for position in grid.positions where position.column == origin.column && position != origin {
                    map.bonuses[position, default: 0] += 1
                }
            }
        case "preparation": add([.init(-1, -1), .init(1, 1, 2)], origin, rotation, grid, &map)
        case "exit": add([.init(-1, 1), .init(0, 1, 2), .init(1, 1)], origin, 0, grid, &map)
        case "tide": add([.init(1, -1, 3), .init(0, -1, -1), .init(1, 0, -1)], origin, rotation, grid, &map)
        case "dedication": add([.init(1, -1), .init(-1, -1), .init(1, 1), .init(-1, 1)], origin, 0, grid, &map)
        case "honor": add([.init(0, -1, 2), .init(-1, -2)], origin, rotation, grid, &map)
        case "rally": add([.init(0, -1, 2), .init(-1, 0, 2)], origin, rotation, grid, &map)
        case "development": add([.init(-1, -1, 2), .init(0, -1), .init(-1, 0)], origin, rotation, grid, &map)
        case "base":
            for position in grid.positions where position.row == origin.row && position != origin {
                map.bonuses[position, default: 0] += 1
            }
        case "warrant": add([.init(0, -1, 3)], origin, rotation, grid, &map)
        case "wedge": add([.init(-1, -1, 3)], origin, rotation, grid, &map)
        case "disconnection": add([.init(0, -1, 3), .init(0, 1, 3), .init(1, 0, -1), .init(-1, 0, -1)], origin, 0, grid, &map)
        case "concurrency":
            for position in grid.positions where position.column == origin.column && position != origin {
                map.bonuses[position, default: 0] += 1
            }
        case "vow": add([.init(0, -2, 2), .init(0, 1), .init(0, -1), .init(-1, 0), .init(1, 0)], origin, rotation, grid, &map)
        case "rebellion":
            let direction = rotation % 2 == 1 ? -1 : 1
            for (dx, dy) in [(direction, -1), (-direction, 1)] {
                var cursor = origin
                while true {
                    cursor = GridPosition(row: cursor.row + dy, column: cursor.column + dx)
                    guard grid.contains(cursor) else { break }
                    map.bonuses[cursor, default: 0] += 1
                }
            }
        case "connection": add([.init(0, -1, 2), .init(0, 1, 0, ignore: true)], origin, rotation, grid, &map)
        case "junction": add([.init(0, -1), .init(0, -2), .init(0, -3), .init(1, 0), .init(2, 0), .init(3, 0)], origin, rotation, grid, &map)
        case "last_stand": add([.init(0, -1, 5), .init(-1, 0, -1), .init(1, 0, -1), .init(0, 1, -1)], origin, 0, grid, &map)
        case "flag":
            if origin.column == 0 {
                add([.init(0, -1), .init(1, 0), .init(2, 0, 2), .init(3, 0, 3), .init(0, 1, -1)], origin, 0, grid, &map)
            }
        case "defender": add([.init(-1, -1), .init(1, -1, 2), .init(-1, 0, -1), .init(1, 0, -1), .init(-1, 1, 2), .init(1, 1)], origin, 0, grid, &map)
        case "shade":
            if origin.row == 0, grid.rowCount >= 2 {
                let lastRow = grid.rowCount - 1
                let previousRow = lastRow - 1
                let bottom = grid.positions.filter { $0.row == lastRow }
                for position in bottom { map.bonuses[position, default: 0] += 1 }
                let bottomColumns = Set(bottom.map(\.column))
                for position in grid.positions where position.row == previousRow && !bottomColumns.contains(position.column) {
                    map.bonuses[position, default: 0] += 1
                }
            }
        case "thorn": add([.init(0, -1, 2), .init(0, 1, 2), .init(-1, -1), .init(-1, 0), .init(-1, 1), .init(1, -1), .init(1, 0), .init(1, 1)], origin, 0, grid, &map)
        case "boundary":
            let firstRow = grid.positions.filter { $0.row == 0 }
            let lastRowIndex = grid.rowCount - 1
            let lastRow = grid.positions.filter { $0.row == lastRowIndex }
            for position in firstRow + lastRow { map.bonuses[position, default: 0] += 1 }
            if lastRowIndex > 0 {
                let lastColumns = Set(lastRow.map(\.column))
                for position in grid.positions where position.row == lastRowIndex - 1 && !lastColumns.contains(position.column) {
                    map.bonuses[position, default: 0] += 1
                }
            }
        case "sheen":
            for position in grid.positions where position != origin {
                if rotation % 2 == 1, position.column == origin.column { map.bonuses[position, default: 0] += 1 }
                if rotation % 2 == 0, position.row == origin.row { map.bonuses[position, default: 0] += 1 }
            }
            add([.init(0, -1, 2), .init(0, 1, 2)], origin, rotation, grid, &map)
        case "miracle":
            for position in grid.positions where position != origin {
                if position.row == origin.row { map.bonuses[position, default: 0] += 1 }
                if position.column == origin.column { map.bonuses[position, default: 0] += 1 }
            }
        case "daydream": add([.init(-1, -1, 2), .init(1, -1, 2), .init(-1, 1, 2), .init(1, 1, 2)], origin, rotation, grid, &map)
        case "compression": add([.init(0, -1, 3), .init(0, -2, 2), .init(0, -3)], origin, rotation, grid, &map)
        case "certitude": add([.init(0, -1, 5)], origin, rotation, grid, &map)
        case "hospitality": add([.init(0, -1, 1, ignore: true), .init(-1, 0, 2, ignore: true)], origin, 0, grid, &map)
        case "peace": add([.init(-1, 0, 3), .init(1, 0, 3)], origin, rotation, grid, &map)
        case "courage": add([.init(-3, -3), .init(-2, -2), .init(-1, -1), .init(1, 1), .init(2, 2), .init(1, -1, 2), .init(-1, 1, 2)], origin, rotation, grid, &map)
        default: break
        }
    }

    private static func add(
        _ offsets: [Offset],
        _ origin: GridPosition,
        _ rotation: Int,
        _ grid: InventoryGrid,
        _ map: inout TabletEffectMap
    ) {
        for offset in offsets {
            let rotated = rotate(dx: offset.dx, dy: offset.dy, by: rotation)
            let target = GridPosition(row: origin.row + rotated.dy, column: origin.column + rotated.dx)
            guard grid.contains(target) else { continue }
            map.bonuses[target, default: 0] += offset.value
            if offset.ignoresCondition { map.ignoredConditions.insert(target) }
        }
    }

    private static func rotate(dx: Int, dy: Int, by rotation: Int) -> (dx: Int, dy: Int) {
        switch ((rotation % 4) + 4) % 4 {
        case 1: (-dy, dx)
        case 2: (-dx, -dy)
        case 3: (dy, -dx)
        default: (dx, dy)
        }
    }
}
