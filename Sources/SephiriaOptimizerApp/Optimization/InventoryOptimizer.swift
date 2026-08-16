import Foundation

enum InventoryEvaluator {
    static func evaluate(_ layout: InventoryLayout) -> LayoutEvaluation {
        let effectMap = TabletEffectEngine.effects(for: layout)
        var artifacts: [ArtifactResult] = []
        var useful = 0
        var full = 0
        var positive = 0
        var overflow = 0
        var negative = 0
        var ignored = 0

        for (position, piece) in layout.pieces {
            guard case .artifact(let artifact) = piece.item else { continue }
            let amplification = effectMap.bonuses[position, default: 0]
            let ignoresCondition = effectMap.ignoredConditions.contains(position)
            let result = ArtifactResult(
                id: piece.id,
                name: artifact.labelKorean,
                position: position,
                amplification: amplification,
                capacity: artifact.capacity,
                ignoresCondition: ignoresCondition
            )
            artifacts.append(result)

            useful += min(max(amplification, 0), max(artifact.capacity, 0))
            if artifact.capacity > 0 && amplification == artifact.capacity { full += 1 }
            if amplification > 0 { positive += 1 }
            overflow += max(0, amplification - artifact.capacity)
            negative += max(0, -amplification)
            if ignoresCondition { ignored += 1 }
        }

        let score = -overflow * 100_000_000
            + useful * 100_000
            + full * 5_000
            + positive * 500
            + ignored * 100
            - negative * 2_000

        return LayoutEvaluation(
            artifacts: artifacts.sorted { $0.position < $1.position },
            totalUsefulAmplification: useful,
            fullArtifactCount: full,
            positiveArtifactCount: positive,
            overflowAmount: overflow,
            negativeAmount: negative,
            ignoredConditionCount: ignored,
            score: score
        )
    }
}

struct InventoryOptimizer: Sendable {
    var iterationsPerRestart = 6_000
    var restartCount = 5

    func optimize(_ input: InventoryLayout, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> OptimizationResult {
        let before = InventoryEvaluator.evaluate(input)
        guard input.pieces.count > 1 else {
            return OptimizationResult(original: input, optimized: input, before: before, after: before, iterations: 0)
        }

        var random = SplitMix64(seed: seed)
        var bestLayout = input
        var bestEvaluation = before
        var totalIterations = 0

        for restart in 0..<max(restartCount, 1) {
            var current = restart == 0 ? input : randomized(input, using: &random)
            var currentEvaluation = InventoryEvaluator.evaluate(current)
            if currentEvaluation.score > bestEvaluation.score {
                bestLayout = current
                bestEvaluation = currentEvaluation
            }

            let iterations = max(iterationsPerRestart, 1)
            for iteration in 0..<iterations {
                totalIterations += 1
                let progress = Double(iteration) / Double(iterations)
                let temperature = max(20, 35_000 * pow(0.002, progress))
                var candidate = current

                if random.nextDouble() < 0.78 {
                    swapMove(&candidate, using: &random)
                } else {
                    rotateMove(&candidate, using: &random)
                }

                let candidateEvaluation = InventoryEvaluator.evaluate(candidate)
                let delta = candidateEvaluation.score - currentEvaluation.score
                let accepted = delta >= 0 || exp(Double(delta) / temperature) > random.nextDouble()
                if accepted {
                    current = candidate
                    currentEvaluation = candidateEvaluation
                }
                if candidateEvaluation.score > bestEvaluation.score {
                    bestLayout = candidate
                    bestEvaluation = candidateEvaluation
                }
            }
        }

        return OptimizationResult(
            original: input,
            optimized: bestLayout,
            before: before,
            after: bestEvaluation,
            iterations: totalIterations
        )
    }

    private func randomized(_ input: InventoryLayout, using random: inout SplitMix64) -> InventoryLayout {
        var pieces = Array(input.pieces.values)
        pieces.shuffle(using: &random)
        let shuffledPositions = input.grid.positions.shuffled(using: &random)
        var output: [GridPosition: InventoryPiece] = [:]
        for (index, var piece) in pieces.enumerated() {
            if case .tablet(let tablet) = piece.item, tablet.isRotatable {
                piece.rotation = random.nextInt(upperBound: 4)
            }
            output[shuffledPositions[index]] = piece
        }
        return InventoryLayout(grid: input.grid, pieces: output)
    }

    private func swapMove(_ layout: inout InventoryLayout, using random: inout SplitMix64) {
        let positions = layout.grid.positions
        guard positions.count >= 2 else { return }
        let first = positions[random.nextInt(upperBound: positions.count)]
        var second = positions[random.nextInt(upperBound: positions.count)]
        if first == second { second = positions[(positions.firstIndex(of: first)! + 1) % positions.count] }
        let firstPiece = layout.pieces[first]
        let secondPiece = layout.pieces[second]
        layout.pieces[first] = secondPiece
        layout.pieces[second] = firstPiece
    }

    private func rotateMove(_ layout: inout InventoryLayout, using random: inout SplitMix64) {
        let rotatable = layout.pieces.compactMap { position, piece -> GridPosition? in
            guard case .tablet(let tablet) = piece.item, tablet.isRotatable else { return nil }
            return position
        }
        guard let position = rotatable.randomElement(using: &random), var piece = layout.pieces[position] else {
            swapMove(&layout, using: &random)
            return
        }
        piece.rotation = (piece.rotation + (random.nextDouble() < 0.5 ? 1 : 3)) % 4
        layout.pieces[position] = piece
    }
}

struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}
