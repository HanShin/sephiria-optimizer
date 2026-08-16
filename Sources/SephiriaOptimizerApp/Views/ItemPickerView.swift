import SwiftUI

struct ItemPickerView: View {
    let position: GridPosition
    let items: [CatalogItem]
    let suggestions: [CatalogItem]
    let capturedCell: NSImage?
    let onSelect: (CatalogItem?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var kind: ItemKind?

    private var filtered: [CatalogItem] {
        items.filter { item in
            (kind == nil || item.kind == kind)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.id.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("\(position.row + 1)행 \(position.column + 1)열")
                    .font(.title2.bold())
                Spacer()
                Picker("종류", selection: $kind) {
                    Text("전체").tag(ItemKind?.none)
                    Text("아티팩트").tag(ItemKind?.some(.artifact))
                    Text("석판").tag(ItemKind?.some(.tablet))
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
            }

            if let capturedCell {
                HStack(spacing: 18) {
                    Image(nsImage: capturedCell)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .padding(8)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("게임에서 캡처한 아이콘")
                            .font(.headline)
                        Text("왼쪽 원본과 아래 후보 그림을 비교해 선택하세요. 교정한 화면은 최대 5장까지 누적 학습됩니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }

            List {
                Button(role: .destructive) {
                    onSelect(nil)
                    dismiss()
                } label: {
                    Label("빈칸으로 설정", systemImage: "trash")
                }
                if query.isEmpty, kind == nil, !suggestions.isEmpty {
                    Section("자동 인식 후보 — 비슷한 그림을 선택하세요") {
                        ForEach(suggestions) { item in
                            itemButton(item)
                        }
                    }
                }
                Section(query.isEmpty ? "전체 아이템" : "검색 결과") {
                ForEach(filtered) { item in
                    itemButton(item)
                }
                }
            }
            .searchable(text: $query, prompt: "아이템 이름 검색")
        }
        .padding(22)
        .frame(minWidth: 720, minHeight: 720)
        .preferredColorScheme(.dark)
    }

    private func itemButton(_ item: CatalogItem) -> some View {
        Button {
            onSelect(item)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: item.imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Color.clear
                            .overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(width: 60, height: 60)
                Text(item.kind == .artifact ? "아티팩트" : "석판")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(item.name)
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
