//
//  WoodMaterial.swift
//  Sleeves
//
//  木製パーツの共通素材。LedgeShelfPluginのレッジ(木目)と
//  StoreShelfPluginの棚板(board)で共有する。
//
//  WoodMaterial: 素材の選択肢。rawValueはsettings.jsonへの
//  永続化値なので一度決めたら変更しない。テクスチャは
//  Assets.xcassetsの `wood-<rawValue>` imageset(目は横目で登録)。
//
//  WoodTexture: Canvas内で木目を描くヘルパー。プラグインの
//  Canvasクロージャ先頭で1回だけ作り、描く要素すべてで使い回す。
//   - baseScale(既定1=等倍=実物の板と同じ物理スケール)で貼る。
//     1より小さくすると木目が細かくなる。rectが縮尺後テクスチャ
//     より大きい場合: repeatsなら拡大せずタイル状に並べて覆い、
//     そうでなければaspect-fillで拡大する(長い棚板が
//     テクスチャ幅を超えるケース)
//   - 切り出し位置はseed(スロットindexや行番号)のsinハッシュで
//     決定論的にずらし、1枚ごとに別の板から切った見え方にする
//   - テクスチャが読めない場合は素材ごとの縦グラデに退く
//   - クリップはコンテキストのコピーに閉じるので、呼び出し側の
//     GraphicsContext(回転済み・後続の影/縁描画)を汚さない
//

import SwiftUI

/// 木製パーツの素材。rawValueはsettings.jsonへの永続化値なので
/// 一度決めたら変更しない
enum WoodMaterial: String, CaseIterable, PluginOption {
    /// 明るい松系のはちみつ色
    case pine
    /// 中間色のオーク
    case oak
    /// 暗いウォールナット
    case walnut
    /// 赤みの強いマホガニー
    case mahogany
    /// 黒に近い黒檀調
    case black

    var label: String {
        switch self {
        case .pine: return "Pine"
        case .oak: return "Oak"
        case .walnut: return "Walnut"
        case .mahogany: return "Mahogany"
        case .black: return "Black"
        }
    }

    /// 木目テクスチャのアセット名(Assets.xcassetsのimageset)。
    /// 目の方向はパーツに合わせて横目で入れてある
    var assetName: String {
        "wood-" + rawValue
    }

    /// 設定メニューの選択肢行に付ける見本(木目サムネイル)
    var icon: PluginParameterSpec.Options.Choice.Icon? {
        .texture(assetName)
    }

    /// 上端がわずかに明るい縦グラデーション(前面が光を拾う)。
    /// テクスチャアセットが読めない場合のフォールバック
    var gradient: Gradient {
        switch self {
        case .pine:
            return Gradient(colors: [
                Color(red: 0xEC/255, green: 0xD2/255, blue: 0xA2/255),
                Color(red: 0xC4/255, green: 0x9E/255, blue: 0x66/255),
            ])
        case .oak:
            return Gradient(colors: [
                Color(red: 0xCB/255, green: 0xA6/255, blue: 0x76/255),
                Color(red: 0x9A/255, green: 0x73/255, blue: 0x49/255),
            ])
        case .walnut:
            return Gradient(colors: [
                Color(red: 0x5A/255, green: 0x44/255, blue: 0x30/255),
                Color(red: 0x38/255, green: 0x29/255, blue: 0x1C/255),
            ])
        case .mahogany:
            return Gradient(colors: [
                Color(red: 0x6E/255, green: 0x32/255, blue: 0x28/255),
                Color(red: 0x48/255, green: 0x20/255, blue: 0x18/255),
            ])
        case .black:
            return Gradient(colors: [
                Color(red: 0x33/255, green: 0x2D/255, blue: 0x27/255),
                Color(red: 0x1D/255, green: 0x19/255, blue: 0x15/255),
            ])
        }
    }
}

/// Canvas内の木目描画ヘルパー。materialのテクスチャを解決して保持する
struct WoodTexture {
    private let image: GraphicsContext.ResolvedImage?
    private let material: WoodMaterial
    /// 基準スケール。1=等倍、0.5なら半分の大きさで貼り
    /// 木目が細かく見える(実験用)
    private let baseScale: CGFloat
    /// trueならrectがbaseScale縮尺の画像を超える次元があるとき、
    /// 画像を拡大せずタイル状に並べて覆う(細かい木目のまま
    /// 長い部材を埋める用)
    private let repeats: Bool

    /// Canvasクロージャの先頭で1回だけ作る
    init(material: WoodMaterial, baseScale: CGFloat = 1,
         repeats: Bool = false, in context: GraphicsContext) {
        self.material = material
        self.baseScale = baseScale
        self.repeats = repeats
        let resolved = context.resolve(Image(material.assetName))
        image = (resolved.size.width > 0 && resolved.size.height > 0)
            ? resolved : nil
    }

    /// テクスチャが解決できたか(フォールバック=グラデ描画かの判定)
    var isAvailable: Bool { image != nil }

    /// pathでクリップして木目をrect全域に描く。
    /// seedで切り出し位置を決定論的にずらす(0なら中央寄り)
    func paint(context: GraphicsContext, path: Path,
               rect: CGRect, seed: Double = 0) {
        guard let image else {
            context.fill(path, with: .linearGradient(
                material.gradient,
                startPoint: CGPoint(x: 0, y: rect.minY),
                endPoint: CGPoint(x: 0, y: rect.maxY)))
            return
        }
        var g = context
        g.clip(to: path)
        // タイルモード: rectがbaseScale縮尺のタイルを超える次元が
        // あるとき、拡大せずbaseScaleのまま並べてrectを覆う
        // (部材がテクスチャより長い場合に木目を細かく保つ。
        //  rectがタイルに収まるときは下の1枚貼りに流れる)
        let tw = image.size.width * baseScale
        let th = image.size.height * baseScale
        if repeats, tw > 0, th > 0,
           rect.width > tw || rect.height > th {
            // タイル格子の位相をhash01でずらし、板ごとに継ぎ目
            // 位置が違う見え方にする(周期パターンなのでずらし
            // 範囲は[0,タイル)の1周期ぶんで十分)
            let offX = Self.hash01(seed, salt: 3.7) * tw
            let offY = Self.hash01(seed, salt: 7.9) * th
            var y = rect.minY - offY
            while y < rect.maxY {
                var x = rect.minX - offX
                while x < rect.maxX {
                    g.draw(image, in: CGRect(
                        x: x, y: y, width: tw, height: th))
                    x += tw
                }
                y += th
            }
            return
        }
        // 基準はbaseScale(既定1=等倍)。rectが縮尺後テクスチャより
        // 大きい次元がある場合だけaspect-fillで拡大
        // (長い棚板がテクスチャ幅を超えるケース)
        let s = max(baseScale,
            rect.width / image.size.width,
            rect.height / image.size.height)
        let w = image.size.width * s
        let h = image.size.height * s
        // 画像の端をrectの端より外へはみ出させる形でずらす
        // (off ∈ [0, 画像-rect])と常にrect全域を覆いつつ
        // 切り出し位置だけ変わる
        let offX = Self.hash01(seed, salt: 3.7) * max(0, w - rect.width)
        let offY = Self.hash01(seed, salt: 7.9) * max(0, h - rect.height)
        g.draw(image, in: CGRect(
            x: rect.minX - offX,
            y: rect.minY - offY,
            width: w, height: h))
    }

    /// 任意シードの決定論疑似乱数(0〜1)。sinハッシュ。
    /// 「その要素はいつも同じ切り出し位置」にする
    private static func hash01(_ seed: Double, salt: Double) -> Double {
        let v = sin(seed * 127.1 + salt * 311.7) * 43758.5453
        return v - v.rounded(.down)
    }
}
