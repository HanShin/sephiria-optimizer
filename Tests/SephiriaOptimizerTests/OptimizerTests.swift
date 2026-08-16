import AppKit
import XCTest
@testable import SephiriaOptimizerApp

final class OptimizerTests: XCTestCase {
    func testThirtyFourSlotGridUsesSixColumnsAndPartialLastRow() {
        let grid = InventoryGrid(slotCount: 34)
        XCTAssertEqual(grid.rowCount, 6)
        XCTAssertEqual(grid.positions.count, 34)
        XCTAssertEqual(grid.positions.last, GridPosition(row: 5, column: 3))
        XCTAssertFalse(grid.contains(GridPosition(row: 5, column: 4)))
    }

    func testCheerTargetsCellAbove() {
        let grid = InventoryGrid(slotCount: 18)
        let origin = GridPosition(row: 1, column: 2)
        let cheer = TabletCatalog.byID["cheer"]!
        let layout = InventoryLayout(
            grid: grid,
            pieces: [origin: InventoryPiece(item: .tablet(cheer))]
        )
        let effects = TabletEffectEngine.effects(for: layout)
        XCTAssertEqual(effects.bonuses[GridPosition(row: 0, column: 2)], 1)
        XCTAssertEqual(effects.bonuses[GridPosition(row: 2, column: 2)], 0)
    }

    func testRotatedApproximationTransformsOffsetsClockwise() {
        let grid = InventoryGrid(slotCount: 18)
        let origin = GridPosition(row: 1, column: 2)
        let tablet = TabletCatalog.byID["approximation"]!
        let layout = InventoryLayout(
            grid: grid,
            pieces: [origin: InventoryPiece(item: .tablet(tablet), rotation: 1)]
        )
        let effects = TabletEffectEngine.effects(for: layout)
        XCTAssertEqual(effects.bonuses[GridPosition(row: 1, column: 3)], 1)
        XCTAssertEqual(effects.bonuses[GridPosition(row: 2, column: 2)], 1)
    }

    func testEvaluatorTreatsAmplificationAboveCapacityAsOverflow() {
        let grid = InventoryGrid(slotCount: 18)
        let artifact = makeArtifact(capacity: 1)
        let warrant = TabletCatalog.byID["warrant"]!
        let layout = InventoryLayout(
            grid: grid,
            pieces: [
                GridPosition(row: 0, column: 0): InventoryPiece(item: .artifact(artifact)),
                GridPosition(row: 1, column: 0): InventoryPiece(item: .tablet(warrant))
            ]
        )
        let evaluation = InventoryEvaluator.evaluate(layout)
        XCTAssertEqual(evaluation.totalUsefulAmplification, 1)
        XCTAssertEqual(evaluation.overflowAmount, 2)
        XCTAssertFalse(evaluation.hasNoOverflow)
    }

    func testOptimizerPreservesPiecesAndFindsUsefulNoOverflowPlacement() {
        let grid = InventoryGrid(slotCount: 18)
        let artifact = makeArtifact(capacity: 1)
        let cheer = TabletCatalog.byID["cheer"]!
        let input = InventoryLayout(
            grid: grid,
            pieces: [
                GridPosition(row: 0, column: 0): InventoryPiece(item: .artifact(artifact)),
                GridPosition(row: 0, column: 5): InventoryPiece(item: .tablet(cheer))
            ]
        )
        let optimizer = InventoryOptimizer(iterationsPerRestart: 800, restartCount: 2)
        let result = optimizer.optimize(input, seed: 42)
        XCTAssertEqual(result.optimized.pieces.count, input.pieces.count)
        XCTAssertTrue(result.after.hasNoOverflow)
        XCTAssertGreaterThanOrEqual(result.after.totalUsefulAmplification, 1)
    }

    func testLiveCellPreprocessingSeparatesEmptyAndOccupiedCellsWhenFixtureExists() throws {
        let emptyURL = URL(fileURLWithPath: "/tmp/sephiria-cell-empty.png")
        let effectEmptyURL = URL(fileURLWithPath: "/tmp/sephiria-cell-effect-empty.png")
        let artifactURL = URL(fileURLWithPath: "/tmp/sephiria-cell-item.png")
        let tabletURL = URL(fileURLWithPath: "/tmp/sephiria-cell-tablet.png")
        let noSlotURL = URL(fileURLWithPath: "/tmp/sephiria-cell-no-slot.png")
        guard FileManager.default.fileExists(atPath: emptyURL.path) else {
            throw XCTSkip("live inventory diagnostic fixture is not available")
        }
        let empty = try loadImage(emptyURL)
        let effectEmpty = try loadImage(effectEmptyURL)
        let artifact = try loadImage(artifactURL)
        let tablet = try loadImage(tabletURL)
        let noSlot = try loadImage(noSlotURL)

        XCTAssertNil(IconNormalizer.normalizeCell(empty))
        XCTAssertNil(IconNormalizer.normalizeCell(effectEmpty))
        XCTAssertNotNil(IconNormalizer.normalizeCell(artifact))
        XCTAssertNotNil(IconNormalizer.normalizeCell(tablet))
        XCTAssertEqual(IconNormalizer.detectedKind(artifact), .artifact)
        XCTAssertEqual(IconNormalizer.detectedKind(tablet), .tablet)
        XCTAssertGreaterThan(IconNormalizer.slotEdgeScore(empty), IconNormalizer.slotEdgeScore(noSlot) * 2)
    }

    func testLiveGridDetectorFindsTwentySlotsWhenFixtureExists() throws {
        let screenshotURL = URL(fileURLWithPath: "/tmp/sephiria-live-inventory.png")
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw XCTSkip("live inventory diagnostic fixture is not available")
        }
        let screenshot = try loadImage(screenshotURL)
        let rect = CGRect(
            x: 650.0 / 1365.0,
            y: 199.0 / 768.0,
            width: 504.0 / 1365.0,
            height: 336.0 / 768.0
        )
        XCTAssertEqual(GridDetector.detectSlotCount(in: screenshot, inventoryRect: rect), 20)

        let outerPanelRect = CGRect(x: 0.4627, y: 0.2446, width: 0.3911, height: 0.4715)
        let correctedRect = ImageUtilities.slotGridRect(fromOuterPanel: outerPanelRect)
        XCTAssertEqual(correctedRect.minX, rect.minX, accuracy: 0.012)
        XCTAssertEqual(correctedRect.minY, rect.minY, accuracy: 0.012)
        XCTAssertEqual(correctedRect.width, rect.width, accuracy: 0.018)
        XCTAssertEqual(correctedRect.height, rect.height, accuracy: 0.018)
        XCTAssertEqual(GridDetector.detectSlotCount(in: screenshot, inventoryRect: correctedRect), 20)

        let cells = ImageUtilities.cellImages(
            from: screenshot,
            inventoryRect: correctedRect,
            grid: InventoryGrid(slotCount: 20)
        )
        XCTAssertEqual(
            IconNormalizer.detectedKind(try XCTUnwrap(cells[GridPosition(row: 0, column: 0)])),
            .artifact
        )
        XCTAssertEqual(
            IconNormalizer.detectedKind(try XCTUnwrap(cells[GridPosition(row: 1, column: 2)])),
            .tablet
        )
    }

    @MainActor
    func testLiveMatcherRejectsEmptyCellsAndReturnsCandidatesForItemsWhenFixtureExists() async throws {
        let emptyURL = URL(fileURLWithPath: "/tmp/sephiria-cell-empty.png")
        guard FileManager.default.fileExists(atPath: emptyURL.path) else {
            throw XCTSkip("live inventory diagnostic fixture is not available")
        }
        let matcher = TemplateMatcher()
        let catalog = try CatalogService.allItems()
        let cachedTemplateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SephiriaOptimizer/Templates/artifact_red_mushroom")
        if FileManager.default.fileExists(atPath: cachedTemplateURL.path) {
            XCTAssertNotNil(IconNormalizer.normalizeTemplate(try loadImage(cachedTemplateURL)))
        }
        try await matcher.prepare(items: catalog, includeLearned: false) { _, _ in }
        let empty = try loadImage(emptyURL)
        let effectEmpty = try loadImage(URL(fileURLWithPath: "/tmp/sephiria-cell-effect-empty.png"))
        let artifact = try loadImage(URL(fileURLWithPath: "/tmp/sephiria-cell-item.png"))
        let tablet = try loadImage(URL(fileURLWithPath: "/tmp/sephiria-cell-tablet.png"))
        XCTAssertTrue(try matcher.topMatches(empty).isEmpty)
        XCTAssertTrue(try matcher.topMatches(effectEmpty).isEmpty)
        let artifactMatches = try matcher.topMatches(artifact, limit: 24)
        let tabletMatches = try matcher.topMatches(tablet)
        XCTAssertFalse(artifactMatches.isEmpty)
        XCTAssertFalse(tabletMatches.isEmpty)
        XCTAssertTrue(artifactMatches.contains { $0.item.id == "artifact:snowborne" })
        XCTAssertLessThan(artifactMatches.firstIndex { $0.item.id == "artifact:snowborne" } ?? .max, 6)
        XCTAssertEqual(tabletMatches.first?.item.id, "tablet:vow")
        XCTAssertEqual(tabletMatches.first?.rotation, 1)

        let snowborne = try XCTUnwrap(catalog.first { $0.id == "artifact:snowborne" })
        let templateCountBeforeLearning = matcher.templateCount
        XCTAssertTrue(matcher.learn(item: snowborne, rotation: 0, from: artifact, persist: false))
        XCTAssertEqual(matcher.templateCount, templateCountBeforeLearning + 1)
        XCTAssertTrue(matcher.learn(item: snowborne, rotation: 0, from: artifact, persist: false))
        XCTAssertEqual(matcher.templateCount, templateCountBeforeLearning + 1)
        XCTAssertEqual(try matcher.topMatches(artifact).first?.item.id, snowborne.id)
    }

    @MainActor
    func testCurrentLiveCaptureFindsOnlyTwoOccupiedCellsWhenFixtureExists() async throws {
        let screenshotURL = URL(fileURLWithPath: "/tmp/sephiria-current-live.jpg")
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw XCTSkip("current live capture fixture is not available")
        }
        let screenshot = try loadImage(screenshotURL)
        let outerPanel = CGRect(x: 0.462686, y: 0.244598, width: 0.391079, height: 0.471463)
        let gridRect = ImageUtilities.slotGridRect(fromOuterPanel: outerPanel)
        XCTAssertEqual(GridDetector.detectSlotCount(in: screenshot, inventoryRect: gridRect), 20)

        let grid = InventoryGrid(slotCount: 20)
        let cells = ImageUtilities.cellImages(from: screenshot, inventoryRect: gridRect, grid: grid)
        let occupied = Set(grid.positions.filter { position in
            guard let cell = cells[position] else { return false }
            return IconNormalizer.detectedKind(cell) != nil
        })
        XCTAssertEqual(
            occupied,
            [GridPosition(row: 1, column: 0), GridPosition(row: 1, column: 2)]
        )

        let catalog = try CatalogService.allItems()
        let matcher = TemplateMatcher()
        try await matcher.prepare(items: catalog, includeLearned: false) { _, _ in }
        let artifactCell = try XCTUnwrap(cells[GridPosition(row: 1, column: 0)])
        let tabletCell = try XCTUnwrap(cells[GridPosition(row: 1, column: 2)])
        XCTAssertTrue(try matcher.topMatches(artifactCell, limit: 24).contains { $0.item.id == "artifact:snowborne" })
        XCTAssertEqual(try matcher.topMatches(tabletCell).first?.item.id, "tablet:vow")
    }

    @MainActor
    func testNewLiveCaptureDetectsTwentySlotsAndSixItemsWhenFixtureExists() async throws {
        let screenshotURL = URL(fileURLWithPath: "/tmp/sephiria-new-live.png")
        guard FileManager.default.fileExists(atPath: screenshotURL.path) else {
            throw XCTSkip("new live capture fixture is not available")
        }
        let screenshot = try loadImage(screenshotURL)
        let gridRect = CGRect(
            x: 431.0 / 1365.0,
            y: 200.0 / 768.0,
            width: 516.0 / 1365.0,
            height: 333.0 / 768.0
        )
        XCTAssertEqual(GridDetector.detectSlotCount(in: screenshot, inventoryRect: gridRect), 20)

        let candidateCells = ImageUtilities.cellImages(
            from: screenshot,
            inventoryRect: gridRect,
            grid: InventoryGrid(slotCount: 24)
        )
        let lastRowScores = (0..<6).map { column in
            IconNormalizer.slotEdgeScore(candidateCells[GridPosition(row: 3, column: column)]!)
        }
        XCTAssertGreaterThan(lastRowScores[0], lastRowScores[2] * 3)
        XCTAssertGreaterThan(lastRowScores[1], lastRowScores[2] * 3)
        let grid = InventoryGrid(slotCount: 20)
        let cells = ImageUtilities.cellImages(from: screenshot, inventoryRect: gridRect, grid: grid)
        let occupied = Set(grid.positions.filter { position in
            guard let cell = cells[position] else { return false }
            return IconNormalizer.detectedKind(cell) != nil
        })
        XCTAssertEqual(occupied, [
            GridPosition(row: 0, column: 2),
            GridPosition(row: 1, column: 0),
            GridPosition(row: 1, column: 1),
            GridPosition(row: 1, column: 2),
            GridPosition(row: 1, column: 3),
            GridPosition(row: 2, column: 2)
        ])
        XCTAssertEqual(IconNormalizer.detectedKind(try XCTUnwrap(cells[GridPosition(row: 1, column: 2)])), .tablet)

        let catalog = try CatalogService.allItems()
        let matcher = TemplateMatcher()
        try await matcher.prepare(items: catalog, includeLearned: false) { _, _ in }
        let expectedItems: [GridPosition: String] = [
            GridPosition(row: 0, column: 2): "artifact:amulet",
            GridPosition(row: 1, column: 0): "artifact:snowborne",
            GridPosition(row: 1, column: 1): "artifact:ice_star",
            GridPosition(row: 1, column: 2): "tablet:harvesting",
            GridPosition(row: 1, column: 3): "artifact:pro",
            GridPosition(row: 2, column: 2): "artifact:small_magic"
        ]
        for (position, itemID) in expectedItems {
            let item = try XCTUnwrap(catalog.first { $0.id == itemID })
            let cell = try XCTUnwrap(cells[position])
            XCTAssertTrue(
                try matcher.topMatches(cell, limit: 24).contains { $0.item.id == itemID },
                "expected candidate \(itemID) at \(position)"
            )
            XCTAssertTrue(matcher.learn(item: item, rotation: 0, from: cell, persist: false))
            let retinaCell = try XCTUnwrap(scaledImage(cell, scale: 2))
            XCTAssertEqual(try matcher.topMatches(retinaCell).first?.item.id, itemID)
        }
    }

    private func makeArtifact(capacity: Int) -> ArtifactDefinition {
        ArtifactDefinition(
            id: 999,
            value: "test_artifact",
            labelKorean: "테스트 아티팩트",
            labelEnglish: "test_artifact",
            tier: "common",
            imageURL: URL(string: "https://example.com/test.png")!,
            capacity: capacity
        )
    }

    private func loadImage(_ url: URL) throws -> CGImage {
        let data = try Data(contentsOf: url)
        guard let image = ImageUtilities.cgImage(from: data) else {
            throw NSError(domain: "OptimizerTests", code: 1)
        }
        return image
    }

    private func scaledImage(_ image: CGImage, scale: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width * scale,
            height: image.height * scale,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale))
        return context.makeImage()
    }
}
