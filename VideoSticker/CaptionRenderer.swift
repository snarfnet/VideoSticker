import UIKit

/// スタンプ上部に文言を白フチ付きで焼き込む。
enum CaptionRenderer {

    /// - Parameters:
    ///   - base: 透過済み（または背景あり）のスタンプ画像
    ///   - caption: 文言と色
    /// - Returns: 文言を焼き込んだ新しい画像（サイズは base と同じ）
    static func draw(on base: UIImage, caption: Caption) -> UIImage {
        let size = base.size
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = base.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))

            let lines = caption.text.components(separatedBy: "\n")
            let lineCount = CGFloat(lines.count)

            // 横幅の 92% に収まるフォントサイズを二分探索的に詰める。
            let maxWidth = size.width * 0.92
            var fontSize = size.height * 0.16
            let longest = lines.max(by: { $0.count < $1.count }) ?? caption.text
            while fontSize > 8 {
                let f = roundedBold(fontSize)
                let w = (longest as NSString).size(withAttributes: [.font: f]).width
                if w <= maxWidth { break }
                fontSize -= 1
            }

            let font = roundedBold(fontSize)
            let lineHeight = font.lineHeight
            let totalHeight = lineHeight * lineCount
            let topPad = size.height * 0.02
            var y = topPad

            let stroke = max(4, fontSize * 0.22)
            for line in lines {
                drawLine(line, font: font, fill: caption.color, strokeWidth: stroke,
                         center: size.width / 2, y: y)
                y += lineHeight
            }
            _ = totalHeight
        }
    }

    private static func roundedBold(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let d = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: d, size: size)
        }
        return base
    }

    private static func drawLine(_ text: String, font: UIFont, fill: UIColor,
                                 strokeWidth: CGFloat, center: CGFloat, y: CGFloat) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center

        // 1) 白フチ（太め）を先に描く
        let outline: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.white,
            .strokeWidth: strokeWidth,            // 正の値＝フチのみ（塗りは白）
            .paragraphStyle: para,
        ]
        let w = (text as NSString).size(withAttributes: [.font: font]).width
        let rect = CGRect(x: center - w / 2 - strokeWidth,
                          y: y,
                          width: w + strokeWidth * 2,
                          height: font.lineHeight + strokeWidth)
        (text as NSString).draw(in: rect, withAttributes: outline)

        // 2) 色塗りを重ねる
        let inner: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fill,
            .paragraphStyle: para,
        ]
        (text as NSString).draw(in: rect, withAttributes: inner)
    }
}
