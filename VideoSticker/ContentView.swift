import SwiftUI

struct ContentView: View {
    @StateObject private var store = StickerStore()

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var processing = false
    @State private var showReview = false
    @State private var showShare = false
    @State private var shareURL: URL?

    // レビュー用の作業状態
    @State private var rawFrames: [UIImage] = []
    @State private var baseFrames: [UIImage] = []
    @State private var detectedGesture: Gesture = .nod
    @State private var reviewSlotID = 1
    @State private var removeBG = true
    @State private var result: StickerBuilder.Result?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.98), Color(red: 0.93, green: 0.95, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(store.slots) { slot in
                            SlotCell(slot: slot)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
            }

            VStack { Spacer(); bottomBar }
        }
        .sheet(isPresented: $showCamera) {
            VideoPicker(source: .camera) { url in process(url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            VideoPicker(source: .library) { url in process(url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReview) { reviewSheet }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .overlay { if processing { ProcessingOverlay() } }
    }

    // MARK: - ヘッダー

    private var header: some View {
        VStack(spacing: 4) {
            Text("動画から動くスタンプ")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.7))
            Text("\(store.filledCount) / 24 個")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - 下部バー

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { showCamera = true } label: {
                barLabel("撮る", system: "video.fill",
                         colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.1, green: 0.35, blue: 0.95)])
            }
            Button { showLibrary = true } label: {
                barLabel("選ぶ", system: "photo.on.rectangle",
                         colors: [Color(red: 0.3, green: 0.7, blue: 0.5), Color(red: 0.15, green: 0.55, blue: 0.4)])
            }
            Button { exportAll() } label: {
                barLabel("書き出し", system: "square.and.arrow.up",
                         colors: [Color(red: 0.95, green: 0.55, blue: 0.2), Color(red: 0.9, green: 0.4, blue: 0.15)])
            }
            .disabled(store.filledCount == 0)
            .opacity(store.filledCount == 0 ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func barLabel(_ title: String, system: String, colors: [Color]) -> some View {
        VStack(spacing: 3) {
            Image(systemName: system).font(.system(size: 18, weight: .bold))
            Text(title).font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 処理

    private func process(_ url: URL) {
        processing = true
        Task {
            let frames = await VideoFrameExtractor.extract(from: url, count: 6)
            guard !frames.isEmpty else {
                await MainActor.run { processing = false }
                return
            }
            let gesture = GestureClassifier.classify(frames)
            let base = StickerBuilder.prepare(rawFrames: frames, removeBG: true)
            let (slotID, cap) = await MainActor.run { () -> (Int, Caption) in
                let id = store.targetSlot(for: gesture)
                return (id, store.slots.first { $0.id == id }!.caption)
            }
            let built = StickerBuilder.compose(baseFrames: base, caption: cap)
            await MainActor.run {
                rawFrames = frames
                baseFrames = base
                detectedGesture = gesture
                reviewSlotID = slotID
                removeBG = true
                result = built
                processing = false
                showReview = true
            }
        }
    }

    private func recompose(captionID: Int) {
        guard let cap = store.slots.first(where: { $0.id == captionID })?.caption else { return }
        processing = true
        Task {
            let built = StickerBuilder.compose(baseFrames: baseFrames, caption: cap)
            await MainActor.run {
                reviewSlotID = captionID
                result = built
                processing = false
            }
        }
    }

    private func rebuildBG(_ remove: Bool) {
        processing = true
        Task {
            let base = StickerBuilder.prepare(rawFrames: rawFrames, removeBG: remove)
            let cap = await MainActor.run { store.slots.first { $0.id == reviewSlotID }!.caption }
            let built = StickerBuilder.compose(baseFrames: base, caption: cap)
            await MainActor.run {
                baseFrames = base
                removeBG = remove
                result = built
                processing = false
            }
        }
    }

    private func saveReview() {
        guard let r = result else { return }
        store.save(slotID: reviewSlotID, apng: r.apng, preview: r.preview, bytes: r.bytes)
        showReview = false
    }

    private func exportAll() {
        processing = true
        let snapshot = store.slots
        Task {
            let url = Exporter.makeZip(slots: snapshot)
            await MainActor.run {
                processing = false
                if let url { shareURL = url; showShare = true }
            }
        }
    }

    // MARK: - レビューシート

    private var reviewSheet: some View {
        let bucket = detectedGesture
        let captions = CaptionBook.captions(for: bucket)
        return VStack(spacing: 16) {
            HStack {
                Button("取り直す") { showReview = false }
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("判定: \(bucket.label)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.95))
                    .overlay(checker.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
                if let r = result {
                    AnimatedFrames(frames: r.preview).padding(20)
                }
            }
            .frame(height: 300)

            if let r = result {
                Text("\(r.bytes / 1024) KB")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(r.bytes <= StickerBuilder.sizeLimit ? Color.secondary : Color.red)
            }

            // バケツ内の文言をスワイプ選択
            VStack(alignment: .leading, spacing: 6) {
                Text("文言（スワイプで変更）")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(captions) { c in
                            let on = c.id == reviewSlotID
                            Button { recompose(captionID: c.id) } label: {
                                Text(c.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(on ? .white : Color(c.color))
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(on ? Color(c.color) : Color(c.color).opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Toggle(isOn: Binding(get: { removeBG }, set: { rebuildBG($0) })) {
                Text("背景を消す").font(.system(size: 15, weight: .semibold))
            }
            .tint(Color(red: 0.2, green: 0.5, blue: 1.0))

            Button { saveReview() } label: {
                Text("このスタンプに決定")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(LinearGradient(colors: [Color(red: 0.2, green: 0.5, blue: 1.0),
                                                        Color(red: 0.1, green: 0.35, blue: 0.95)],
                                               startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(result == nil)
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDragIndicator(.visible)
    }

    private var checker: some View {
        GeometryReader { geo in
            let s: CGFloat = 14
            let cols = Int(geo.size.width / s) + 1
            let rows = Int(geo.size.height / s) + 1
            Path { p in
                for r in 0..<rows { for c in 0..<cols where (r + c) % 2 == 0 {
                    p.addRect(CGRect(x: CGFloat(c) * s, y: CGFloat(r) * s, width: s, height: s))
                }}
            }
            .fill(Color(white: 0.88))
        }
    }
}

// MARK: - スロットセル

private struct SlotCell: View {
    let slot: StickerStore.Slot

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                if slot.filled, let first = slot.preview.first {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(slot.caption.color).opacity(0.6))
                        Text(slot.caption.text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(slot.caption.color).opacity(slot.filled ? 0.9 : 0.25),
                                  lineWidth: slot.filled ? 2 : 1)
            )
            Text("\(slot.caption.id)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProcessingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text("作成中…")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
