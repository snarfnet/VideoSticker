import UIKit

/// 動きのバケツ。撮った動画を判定してこのいずれかに振り分ける。
enum Gesture: String, CaseIterable, Identifiable {
    case bow    // お辞儀（深い謝罪・お願い）
    case wave   // 手を振る・挨拶
    case ok     // OKサイン（指）
    case fist   // ガッツポーズ（握りこぶし）
    case palm   // 手のひら（待って）
    case nod    // 会釈・その他

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bow:  return "お辞儀"
        case .wave: return "手を振る"
        case .ok:   return "OKサイン"
        case .fist: return "ガッツ"
        case .palm: return "手のひら"
        case .nod:  return "会釈"
        }
    }
}

struct Caption: Identifiable, Equatable {
    let id: Int          // 1...24（スタンプ番号）
    let text: String     // 焼き込む文言（改行は \n）
    let gesture: Gesture // 属するバケツ
    let rgb: (UInt8, UInt8, UInt8) // 文字の塗り色

    var color: UIColor {
        UIColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
                blue: CGFloat(rgb.2) / 255, alpha: 1)
    }

    static func == (a: Caption, b: Caption) -> Bool { a.id == b.id }
}

enum CaptionBook {
    // 青/緑/橙/紫 をバケツごとに割り当て、LINEらしい白フチ前提の鮮やか色にする。
    static let blue:   (UInt8, UInt8, UInt8) = (28, 86, 214)
    static let green:  (UInt8, UInt8, UInt8) = (28, 165, 92)
    static let orange: (UInt8, UInt8, UInt8) = (240, 120, 20)
    static let purple: (UInt8, UInt8, UInt8) = (150, 60, 200)
    static let pink:   (UInt8, UInt8, UInt8) = (232, 60, 130)

    static let all: [Caption] = [
        // bow（お辞儀）
        Caption(id: 1,  text: "申し訳\nございません", gesture: .bow,  rgb: blue),
        Caption(id: 2,  text: "すみません",          gesture: .bow,  rgb: blue),
        Caption(id: 3,  text: "失礼いたしました",     gesture: .bow,  rgb: blue),
        Caption(id: 4,  text: "ご迷惑を\nおかけしました", gesture: .bow, rgb: blue),
        Caption(id: 5,  text: "失礼します",          gesture: .bow,  rgb: blue),
        Caption(id: 6,  text: "お願いいたします",     gesture: .bow,  rgb: blue),
        Caption(id: 7,  text: "ぺこり",              gesture: .bow,  rgb: blue),
        // palm（手のひら・待って）
        Caption(id: 8,  text: "少々お待ちください",   gesture: .palm, rgb: green),
        Caption(id: 9,  text: "お待たせしました",     gesture: .palm, rgb: green),
        Caption(id: 10, text: "ただいま\n確認します",  gesture: .palm, rgb: green),
        // fist（ガッツ）
        Caption(id: 11, text: "至急対応します",       gesture: .fist, rgb: orange),
        Caption(id: 12, text: "修正いたします",       gesture: .fist, rgb: orange),
        Caption(id: 13, text: "助かりました",         gesture: .fist, rgb: orange),
        // nod（会釈・その他）
        Caption(id: 14, text: "先ほどの件ですが…",    gesture: .nod,  rgb: purple),
        Caption(id: 15, text: "再度ご連絡します",     gesture: .nod,  rgb: purple),
        Caption(id: 16, text: "恐れ入ります",         gesture: .nod,  rgb: purple),
        Caption(id: 17, text: "ありがとう\nございます", gesture: .nod, rgb: pink),
        // ok（OKサイン）
        Caption(id: 18, text: "確認OKです",          gesture: .ok,   rgb: green),
        Caption(id: 19, text: "かしこまりました",     gesture: .ok,   rgb: green),
        Caption(id: 20, text: "承知しました",         gesture: .ok,   rgb: green),
        // wave（手を振る・挨拶）
        Caption(id: 21, text: "はい！",              gesture: .wave, rgb: blue),
        Caption(id: 22, text: "お疲れさまです",       gesture: .wave, rgb: pink),
        Caption(id: 23, text: "ただいま伺います",     gesture: .wave, rgb: blue),
        Caption(id: 24, text: "すぐ戻ります",         gesture: .wave, rgb: orange),
    ]

    static func captions(for gesture: Gesture) -> [Caption] {
        all.filter { $0.gesture == gesture }
    }
}
