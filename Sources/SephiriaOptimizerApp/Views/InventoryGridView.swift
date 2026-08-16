import SwiftUI

struct InventoryGridView: View {
    let layout: InventoryLayout
    let evaluation: LayoutEvaluation
    let editable: Bool
    let unresolvedPositions: Set<GridPosition>
    let onSelect: (GridPosition) -> Void
    let onRotate: (GridPosition) -> Void

    private let cellWidth: CGFloat = 112
    private let cellHeight: CGFloat = 92
    private let spacing: CGFloat = 8

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: 6)
    }

    var body: some View {
        let resultByPosition = Dictionary(uniqueKeysWithValues: evaluation.artifacts.map { ($0.position, $0) })
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(layout.grid.positions) { position in
                let piece = layout.pieces[position]
                let artifact = resultByPosition[position]
                Button {
                    if editable { onSelect(position) }
                } label: {
                    cell(
                        position: position,
                        piece: piece,
                        artifact: artifact,
                        isUnresolved: unresolvedPositions.contains(position)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if editable {
                        Button("아이템 변경") { onSelect(position) }
                        if let piece, case .tablet(let tablet) = piece.item, tablet.isRotatable {
                            Button("90° 회전") { onRotate(position) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.075, green: 0.055, blue: 0.085))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func cell(
        position: GridPosition,
        piece: InventoryPiece?,
        artifact: ArtifactResult?,
        isUnresolved: Bool
    ) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(cellColor(piece, isUnresolved: isUnresolved))
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isUnresolved ? Color.orange : artifact?.overflow ?? 0 > 0 ? Color.yellow : Color.white.opacity(0.25),
                    lineWidth: isUnresolved ? 3 : 2
                )

            Text("\(position.row + 1),\(position.column + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .padding(7)

            if let piece {
                VStack(spacing: 5) {
                    Spacer(minLength: 18)
                    Text(piece.item.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if case .tablet(let tablet) = piece.item, tablet.isRotatable {
                        Text("↻ \(piece.rotation * 90)°")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                    } else if let artifact {
                        Text("+\(artifact.amplification) / \(artifact.capacity)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(artifact.overflow > 0 ? .yellow : artifact.amplification == artifact.capacity ? .green : .white)
                    }
                    if piece.recognitionConfidence < 0.35 {
                        Text("확인 필요")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
            } else if editable {
                if isUnresolved {
                    VStack(spacing: 4) {
                        Image(systemName: "questionmark.circle.fill")
                        Text("확인 필요")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: cellWidth, height: cellHeight)
    }

    private func cellColor(_ piece: InventoryPiece?, isUnresolved: Bool) -> Color {
        if isUnresolved { return Color(red: 0.42, green: 0.22, blue: 0.12) }
        guard let piece else { return Color(red: 0.17, green: 0.14, blue: 0.20) }
        switch piece.item {
        case .artifact: return Color(red: 0.34, green: 0.23, blue: 0.46)
        case .tablet: return Color(red: 0.11, green: 0.29, blue: 0.39)
        }
    }
}
