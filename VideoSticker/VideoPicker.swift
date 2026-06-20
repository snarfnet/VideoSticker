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
        }
        p.delegate = context.coordinator
        return p
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
