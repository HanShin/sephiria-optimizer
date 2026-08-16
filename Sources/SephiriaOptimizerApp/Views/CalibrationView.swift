import AppKit
import SwiftUI

struct CalibrationView: View {
    let image: NSImage
    let initialRect: CGRect
    let onConfirm: (CGRect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: CGRect
    @State private var dragStart: CGPoint?

    init(image: NSImage, initialRect: CGRect, onConfirm: @escaping (CGRect) -> Void) {
        self.image = image
        self.initialRect = initialRect
        self.onConfirm = onConfirm
        _selection = State(initialValue: initialRect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("인벤토리 영역 지정")
                .font(.title2.bold())
            Text("첫 번째 슬롯의 왼쪽 위 바깥선부터 마지막 슬롯의 오른쪽 아래 바깥선까지, 슬롯 격자만 정확히 드래그하세요. 갈색 판의 넓은 여백은 포함하지 마세요.")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let frame = fittedImageFrame(in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.9)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)

                    Rectangle()
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [7, 4]))
                        .background(Color.yellow.opacity(0.12))
                        .frame(width: selection.width * frame.width, height: selection.height * frame.height)
                        .offset(
                            x: frame.minX + selection.minX * frame.width,
                            y: frame.minY + selection.minY * frame.height
                        )

                    gridOverlay(frame: frame)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = normalized(value.location, in: frame)
                            if dragStart == nil { dragStart = point }
                            guard let start = dragStart else { return }
                            selection = CGRect(
                                x: min(start.x, point.x),
                                y: min(start.y, point.y),
                                width: abs(point.x - start.x),
                                height: abs(point.y - start.y)
                            )
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("취소") { dismiss() }
                Spacer()
                Button("이 영역 사용") { onConfirm(selection) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.width < 0.03 || selection.height < 0.03)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 650)
    }

    @ViewBuilder
    private func gridOverlay(frame: CGRect) -> some View {
        let rect = CGRect(
            x: frame.minX + selection.minX * frame.width,
            y: frame.minY + selection.minY * frame.height,
            width: selection.width * frame.width,
            height: selection.height * frame.height
        )
        Canvas { context, _ in
            guard rect.width > 0, rect.height > 0 else { return }
            for column in 1..<6 {
                let x = rect.minX + rect.width * CGFloat(column) / 6
                var path = Path()
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(path, with: .color(.yellow.opacity(0.55)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func fittedImageFrame(in container: CGSize) -> CGRect {
        let imageAspect = image.size.width / max(image.size.height, 1)
        let containerAspect = container.width / max(container.height, 1)
        let size: CGSize
        if imageAspect > containerAspect {
            size = CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            size = CGSize(width: container.height * imageAspect, height: container.height)
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalized(_ point: CGPoint, in frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((point.x - frame.minX) / max(frame.width, 1), 0), 1),
            y: min(max((point.y - frame.minY) / max(frame.height, 1), 0), 1)
        )
    }
}
