import SwiftUI
import UIKit

/// 24スロット（=固定文言）の状態を持つ。
@MainActor
final class StickerStore: ObservableObject {
    struct Slot: Identifiable {
        let caption: Caption
        var apng: Data? = nil
        var preview: [UIImage] = []
        var bytes: Int = 0
        var id: Int { caption.id }
        var filled: Bool { apng != nil }
    }

    @Published var slots: [Slot] = CaptionBook.all.map { Slot(caption: $0) }

    var filledCount: Int { slots.filter { $0.filled }.count }

    func index(of id: Int) -> Int? { slots.firstIndex { $0.id == id } }

    /// バケツ内で最初の空きスロットID。無ければバケツ先頭ID。
    func targetSlot(for gesture: Gesture) -> Int {
        let inBucket = slots.filter { $0.caption.gesture == gesture }
        if let empty = inBucket.first(where: { !$0.filled }) { return empty.id }
        return inBucket.first?.id ?? slots[0].id
    }

    func save(slotID: Int, apng: Data, preview: [UIImage], bytes: Int) {
        guard let i = index(of: slotID) else { return }
        slots[i].apng = apng
        slots[i].preview = preview
        slots[i].bytes = bytes
    }

    func clear(slotID: Int) {
        guard let i = index(of: slotID) else { return }
        slots[i].apng = nil
        slots[i].preview = []
        slots[i].bytes = 0
    }
}

/// フレーム配列をパラパラ表示するアニメビュー。
struct AnimatedFrames: View {
    let frames: [UIImage]
    var fps: Double = 6
    @State private var idx = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.clear
            } else {
                Image(uiImage: frames[min(idx, frames.count - 1)])
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        timer?.invalidate()
        guard frames.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / max(1, fps), repeats: true) { _ in
            idx = (idx + 1) % frames.count
        }
    }
}

/// 書き出し: 01.png..NN.png(APNG) + main.png + tab.png をフォルダに置き、ZIP化して共有。
enum Exporter {
    /// - Returns: 共有用 ZIP の URL（temp）
    static func makeZip(slots: [StickerStore.Slot]) -> URL? {
        let filled = slots.filter { $0.filled }
        guard !filled.isEmpty else { return nil }

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("line_stickers_\(Int(Date().timeIntervalSince1970))")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        for slot in filled {
            guard let data = slot.apng else { continue }
            let name = String(format: "%02d.png", slot.caption.id)
            try? data.write(to: dir.appendingPathComponent(name))
        }
        // main(240x240) / tab(96x74) を先頭スタンプから生成。
        if let first = filled.first, let frame = first.preview.first {
            if let main = staticPNG(frame, size: CGSize(width: 240, height: 240)) {
                try? main.write(to: dir.appendingPathComponent("main.png"))
            }
            if let tab = staticPNG(frame, size: CGSize(width: 96, height: 74)) {
                try? tab.write(to: dir.appendingPathComponent("tab.png"))
            }
        }
        return zipDirectory(dir)
    }

    private static func staticPNG(_ image: UIImage, size: CGSize) -> Data? {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.opaque = false
        fmt.scale = 1
        let r = UIGraphicsImageRenderer(size: size, format: fmt)
        let img = r.image { _ in
            let s = min(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * s, h = image.size.height * s
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
        return img.pngData()
    }

    /// NSFileCoordinator の forUploading でディレクトリを zip 化。
    private static func zipDirectory(_ dir: URL) -> URL? {
        var zipURL: URL?
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: dir, options: [.forUploading], error: &coordError) { tmp in
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dst)
            try? FileManager.default.copyItem(at: tmp, to: dst)
            zipURL = dst
        }
        return zipURL
    }
}

/// 共有シート。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
