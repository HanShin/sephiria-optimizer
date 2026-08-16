import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @State private var showResetLearningConfirmation = false

    var body: some View {
        NavigationSplitView {
            controls
                .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 380)
        } detail: {
            resultArea
        }
        .frame(minWidth: 1_280, minHeight: 800)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showCalibration) {
            if let image = model.capturedImage {
                CalibrationView(image: image, initialRect: model.calibrationRect, onConfirm: model.applyCalibration)
            }
        }
        .sheet(item: $model.selectedPosition) { position in
            ItemPickerView(
                position: position,
                items: model.catalog,
                suggestions: model.recognitionSuggestions[position] ?? [],
                capturedCell: model.cellPreviews[position]
            ) { item in
                model.setItem(item, at: position)
            }
        }
        .confirmationDialog(
            "저장된 인식 학습을 초기화할까요?",
            isPresented: $showResetLearningConfirmation,
            titleVisibility: .visible
        ) {
            Button("학습 데이터 초기화", role: .destructive) {
                model.resetRecognitionLearning()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("잘못 선택해 누적된 아이템 화면만 지웁니다. 아이템 목록과 설정은 유지됩니다.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sephiria Optimizer")
                    .font(.title.bold())
                Text("읽기 전용 화면 인식 도구")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.captureFromGame()
            } label: {
                Label("게임 인벤토리 캡처", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)

            Text("게임에서 인벤토리를 연 뒤 F8\n작동하지 않으면 ⌥⌘I")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Stepper("인벤토리 \(model.slotCount)칸", value: $model.slotCount, in: 18...60)
            Button("인벤토리 영역 다시 지정") { model.recalibrate() }
                .disabled(model.capturedImage == nil)
            Button("현재 입력으로 다시 최적화") { model.optimizeCurrent() }
                .disabled(model.recognizedLayout == nil || model.isBusy)
            Button("잘못된 인식 학습 초기화", role: .destructive) {
                showResetLearningConfirmation = true
            }

            Toggle("게임 위에 창 유지", isOn: $model.keepWindowOnTop)

            Divider()

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.status)
                .font(.body.weight(.medium))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            if !model.templateProgress.isEmpty {
                Text(model.templateProgress)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let result = model.result {
                Divider()
                metric("유효 증폭", result.before.totalUsefulAmplification, result.after.totalUsefulAmplification)
                metric("최대 증폭 아티팩트", result.before.fullArtifactCount, result.after.fullArtifactCount)
                metric("초과량", result.before.overflowAmount, result.after.overflowAmount, lowerIsBetter: true)
                metric("음수 영향", result.before.negativeAmount, result.after.negativeAmount, lowerIsBetter: true)
            }

            Spacer()
            Text("화면과 공개 아이템 정보만 읽으며 게임 파일·세이브·입력을 변경하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
    }

    @ViewBuilder
    private func metric(_ title: String, _ before: Int, _ after: Int, lowerIsBetter: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(before) → \(after)")
                .monospacedDigit()
                .foregroundStyle((lowerIsBetter ? after <= before : after >= before) ? .green : .orange)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var resultArea: some View {
        if let layout = model.recognizedLayout {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("현재 인식 결과")
                        .font(.title2.bold())
                    Text("‘확인 필요’ 칸을 클릭해 수정하면 해당 아티팩트의 화면 모습을 학습합니다. 회전 가능한 석판은 우클릭하세요.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    InventoryGridView(
                        layout: layout,
                        evaluation: model.result?.before ?? InventoryEvaluator.evaluate(layout),
                        editable: true,
                        unresolvedPositions: model.unresolvedPositions,
                        onSelect: { model.selectedPosition = $0 },
                        onRotate: model.rotatePiece
                    )

                    if let result = model.result {
                        Divider()
                        HStack {
                            Text("추천 배치")
                                .font(.title2.bold())
                            if result.after.hasNoOverflow {
                                Label("증폭 초과 없음", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("초과 \(result.after.overflowAmount)", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                        }
                        InventoryGridView(
                            layout: result.optimized,
                            evaluation: result.after,
                            editable: false,
                            unresolvedPositions: [],
                            onSelect: { _ in },
                            onRotate: { _ in }
                        )
                    }
                }
                .padding(28)
            }
        } else if let image = model.capturedImage {
            VStack(spacing: 14) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                Button("인벤토리 영역 지정") { model.recalibrate() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView(
                "인벤토리를 기다리는 중",
                systemImage: "square.grid.3x3",
                description: Text("Sephiria에서 인벤토리를 열고 F8 또는 ⌥⌘I를 누르세요.")
            )
        }
    }
}
