import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 動画を撮影 or アルバムから選ぶ（UIImagePickerController ラッパー）。
struct VideoPicker: UIViewControllerRepresentable {
    enum Source { case camera, library }
    let source: Source
    let onPicked: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = source == .camera ? .camera : .photoLibrary
        p.mediaTypes = [UTType.movie.identifier]
        if source == .camera {
            p.cameraCaptureMode = .video
            p.videoMaximumDuration = 15   // 6種類の動きを1本に収めるため長めに
            p.videoQuality = .typeHigh
            // 証明写真風の黄色いガイド枠＋ポーズの順番を重ねる
            p.cameraOverlayView = Self.makeGuideOverlay()
        }
        p.delegate = context.coordinator
        return p
    }

    /// 撮影ガイドのオーバーレイ（黄色い枠 + ポーズ順）。タップは透過してシステムの録画ボタンを邪魔しない。
    private static func makeGuideOverlay() -> UIView {
        let screen = UIScreen.main.bounds
        let overlay = UIView(frame: screen)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        // 頭〜肩を合わせる黄色いだ円ガイド（証明写真風）
        let guideW = screen.width * 0.60
        let guideH = guideW * 1.28
        let guideRect = CGRect(x: (screen.width - guideW) / 2,
                               y: screen.height * 0.20,
                               width: guideW, height: guideH)
        let guide = CAShapeLayer()
        guide.path = UIBezierPath(roundedRect: guideRect, cornerRadius: guideW * 0.46).cgPath
        guide.strokeColor = UIColor.systemYellow.cgColor
        guide.fillColor = UIColor.clear.cgColor
        guide.lineWidth = 3
        guide.lineDashPattern = [10, 6]
        overlay.layer.addSublayer(guide)

        // ポーズの順番＋ヒント。上部はシステムの録画タイマー（赤い数字）専用に空け、
        // ガイド説明はすべて画面下部（録画ボタンの上）にまとめる。
        let steps = UILabel()
        steps.numberOfLines = 0
        steps.textAlignment = .center
        steps.text = "黄色い枠に体を合わせて、順番に動いてください\n① お辞儀 → ② 手を振る → ③ OKサイン\n→ ④ ガッツポーズ → ⑤ 手のひら → ⑥ 会釈\n各ポーズを2〜3秒キープ"
        steps.font = .systemFont(ofSize: 14, weight: .bold)
        steps.textColor = .white
        steps.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        steps.layer.cornerRadius = 12
        steps.clipsToBounds = true
        steps.frame = CGRect(x: 16, y: screen.height - 270, width: screen.width - 32, height: 100)
        overlay.addSubview(steps)

        return overlay
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (URL) -> Void
        init(onPicked: @escaping (URL) -> Void) { self.onPicked = onPicked }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let url = info[.mediaURL] as? URL { onPicked(url) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
