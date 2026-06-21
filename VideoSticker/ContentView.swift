import SwiftUI

struct ContentView: View {
    @StateObject private var store = StickerStore()

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var processing = false
    @State private var progressText = "作成中…"
    @State private var showShare = false
    @State private var shareURL: URL?

    // 撮影前の背景設定（全スタンプ共通）
    @State private var removeBG = true

    // バケツ別の作業フレーム（背景切替・微調整の再生成に使う）
    @State private var rawByGesture: [Gesture: [UIImage]] = [:]
    @State private var baseByGesture: [Gesture: [UIImage]] = [:]

    // 個別プレビュー
    @State private var showReview = false
    @State private var reviewSlotID = 1

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.98), Color(red: 0.93, green: 0.95, blue: 1.0)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    guideCard
                    bgPicker
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(store.slots) { slot in
                            SlotCell(slot: slot)
                                .onTapGesture { openReview(slot) }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 120)
                }
            }

            VStack { Spacer(); bottomBar }

            // 左上に控えめなサンプルボタン。
            VStack {
                HStack {
                    sampleButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.top, 6)
        }
        .sheet(isPresented: $showCamera) {
            VideoPicker(source: .camera) { url in processAll(url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            VideoPicker(source: .library) { url in processAll(url) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReview) { reviewSheet }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { ShareSheet(items: [url]) }
        }
        .overlay { if processing { ProcessingOverlay(text: progressText) } }
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

    // MARK: - 案内カード

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1本の動画から24個のスタンプを自動で作ります")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.3, blue: 0.7))
            Text("お辞儀 → 手を振る → OKサイン → ガッツポーズ → 手のひら → 会釈、と順番に動いてください。各ポーズは1〜2秒キープすると、動きを見分けて枠に振り分けます。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.7)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - サンプル動画で試す（同梱動画でその場でスタンプ化）

    private var sampleButton: some View {
        Button { runSample() } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                Text("サンプル")
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.7)))
        }
    }

    private func runSample() {
        guard let url = Bundle.main.url(forResource: "sample_salaryman", withExtension: "mp4") else { return }
        processAll(url)
    }

    // MARK: - 背景の選択（撮影前）

    private var bgPicker: some View {
        HStack(spacing: 10) {
            Text("背景")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
            Picker("背景", selection: $removeBG) {
                Text("透過する").tag(true)
                Text("透過しない").tag(false)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
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

    // MARK: - 1動画 → 24枠 自動振り分け

    private func processAll(_ url: URL) {
        processing = true
        progressText = "フレームを解析中…"
        let remove = removeBG
        Task {
            // 多めに抽出して、各フレームの動きを個別に判定。
            let frames = await VideoFrameExtractor.extract(from: url, count: 30)
            guard !frames.isEmpty else {
                await MainActor.run { processing = false }
                return
            }
            // 動画を時間順に6等分し、撮影ガイドの順番でバケツへ割り当てる。
            // 動き判定が弱くても（動物・物でも）必ず6バケツ＝24枠すべてを埋める。
            let order: [Gesture] = [.bow, .wave, .ok, .fist, .palm, .nod]
            let n = frames.count
            var byG: [Gesture: [UIImage]] = [:]
            for (i, g) in order.enumerated() {
                let lo = i * n / order.count
                let hi = (i + 1) * n / order.count
                byG[g] = lo < hi ? Array(frames[lo..<hi]) : [frames[min(lo, n - 1)]]
            }

            var newRaw: [Gesture: [UIImage]] = [:]
            var newBase: [Gesture: [UIImage]] = [:]
            var built: [(Int, StickerBuilder.Result)] = []

            for gesture in Gesture.allCases {
                guard let pool = byG[gesture], !pool.isEmpty else { continue }
                let picked = sample(pool, 8)
                let base = StickerBuilder.prepare(rawFrames: picked, removeBG: remove)
                guard !base.isEmpty else { continue }
                newRaw[gesture] = picked
                newBase[gesture] = base
                for cap in CaptionBook.captions(for: gesture) {
                    if let r = StickerBuilder.compose(baseFrames: base, caption: cap) {
                        built.append((cap.id, r))
                    }
                }
            }

            await MainActor.run {
                rawByGesture.merge(newRaw) { _, n in n }
                baseByGesture.merge(newBase) { _, n in n }
                for (id, r) in built {
                    store.save(slotID: id, apng: r.apng, preview: r.preview, bytes: r.bytes)
                }
                processing = false
            }
        }
    }

    /// 配列から最大 k 枚を等間隔で抜く。
    private func sample(_ a: [UIImage], _ k: Int) -> [UIImage] {
        guard a.count > k else { return a }
        if k <= 1 { return [a[a.count / 2]] }
        return (0..<k).map { a[$0 * (a.count - 1) / (k - 1)] }
    }

    // MARK: - 個別プレビュー / 微調整

    private func openReview(_ slot: StickerStore.Slot) {
        reviewSlotID = slot.id
        showReview = true
    }

    private var reviewGesture: Gesture {
        store.slots.first { $0.id == reviewSlotID }?.caption.gesture ?? .nod
    }

    /// 背景設定を変えてこのバケツを作り直し、所属する全枠を更新。
    private func rebuildBucket(remove: Bool) {
        let g = reviewGesture
        guard let raw = rawByGesture[g] else { return }
        processing = true
        progressText = "作り直し中…"
        Task {
            let base = StickerBuilder.prepare(rawFrames: raw, removeBG: remove)
            var built: [(Int, StickerBuilder.Result)] = []
            for cap in CaptionBook.captions(for: g) {
                if let r = StickerBuilder.compose(baseFrames: base, caption: cap) {
                    built.append((cap.id, r))
                }
            }
            await MainActor.run {
                baseByGesture[g] = base
                for (id, r) in built {
                    store.save(slotID: id, apng: r.apng, preview: r.preview, bytes: r.bytes)
                }
                processing = false
            }
        }
    }

    private func exportAll() {
        processing = true
        progressText = "書き出し中…"
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
        let slot = store.slots.first { $0.id == reviewSlotID }
        let g = reviewGesture
        let detected = baseByGesture[g] != nil
        return VStack(spacing: 16) {
            HStack {
                Button("閉じる") { showReview = false }
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(g.label)・\(slot?.caption.text.replacingOccurrences(of: "\n", with: " ") ?? "")")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.95))
                    .overlay(checker.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
                if let frames = slot?.preview, !frames.isEmpty {
                    AnimatedFrames(frames: frames).padding(20)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text(detected ? "このスタンプは未作成です"
                                       : "この動きは検出されませんでした。\nもう一度その動きを入れて撮り直してください。")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(height: 300)

            if let bytes = slot?.bytes, bytes > 0 {
                Text("\(bytes / 1024) KB")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(bytes <= StickerBuilder.sizeLimit ? Color.secondary : Color.red)
            }

            if detected {
                Toggle(isOn: Binding(get: { removeBG }, set: { removeBG = $0; rebuildBucket(remove: $0) })) {
                    Text("背景を透過する").font(.system(size: 15, weight: .semibold))
                }
                .tint(Color(red: 0.2, green: 0.5, blue: 1.0))

                if slot?.filled == true {
                    Button(role: .destructive) {
                        store.clear(slotID: reviewSlotID)
                    } label: {
                        Text("この枠を消す")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
            }
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
    var text: String = "作成中…"
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.4).tint(.white)
                Text(text)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
