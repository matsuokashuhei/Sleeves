//
//  AppIconImageProcessor.swift
//  Sleeves
//
//  Created by Shuhei Matsuoka on 2026/11/28.
//

import CoreGraphics
import Foundation
import ImageIO

/// カスタム App Icon 用画像の正規化ロジック。
/// AppKit に依存せず Foundation / CoreGraphics / ImageIO のみで構成し、
/// アプリ本体(Sleeves)と単体テスト(SleevesTests)の双方から直接利用する。
enum AppIconImageProcessor {

    /// Dock アイコン合成の中央タイル1辺(AppIconManager.iconTileSize と同じ)
    static let defaultTargetSize = 824

    /// 非正方形画像から中央正方形を切り出す矩形を返す(ピクセル座標)。
    /// width または height が 0 以下のときは .zero。
    static func centerSquareCropRect(width: Int, height: Int) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        let side = min(width, height)
        let x = (width - side) / 2
        let y = (height - side) / 2
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// 任意の画像データを EXIF orientation 適用 → 中央正方形クロップ(Aspect Fill)
    /// → targetSize × targetSize の sRGB PNG へ正規化する。
    /// 透過 PNG はアルファを維持する。不正データやサイズ 0 等は nil を返す。
    static func normalizeSquarePNG(from data: Data, targetSize: Int = defaultTargetSize) -> Data? {
        guard !data.isEmpty, targetSize > 0 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let rawWidth = cgImage.width
        let rawHeight = cgImage.height
        guard rawWidth > 0, rawHeight > 0 else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up

        // EXIF orientation 5〜8 は 90°/270° 回転を含むため正立時の幅と高さが入れ替わる
        let swapsAxes = isSwappedAxes(orientation)
        let uprightWidth = swapsAxes ? rawHeight : rawWidth
        let uprightHeight = swapsAxes ? rawWidth : rawHeight

        let cropRect = centerSquareCropRect(width: uprightWidth, height: uprightHeight)
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high

        // 1パスで「正立変換 → 中央正方形クロップ → targetSize へスケーリング」を合成する。
        // 巨大な写真を正立用の中間ビットマップに展開せずに済むためメモリ消費を抑えられる。
        let scale = CGFloat(targetSize) / cropRect.width
        // CGContext は左下原点のため、上端基準の cropRect.origin.y を左下基準へ換算する
        let cgCropOriginY = CGFloat(uprightHeight) - cropRect.maxY
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -cropRect.origin.x, y: -cgCropOriginY)
        applyOrientationTransform(
            orientation,
            rawWidth: CGFloat(rawWidth),
            rawHeight: CGFloat(rawHeight),
            to: context
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: rawWidth, height: rawHeight))

        guard let outputImage = context.makeImage() else { return nil }
        return encodePNG(outputImage)
    }

    // MARK: - EXIF orientation

    private static func isSwappedAxes(_ orientation: CGImagePropertyOrientation) -> Bool {
        switch orientation {
        case .leftMirrored, .right, .rightMirrored, .left:
            return true
        default:
            return false
        }
    }

    /// 生画像(CG座標系: 左下原点, サイズ rawWidth×rawHeight)を正立画像
    /// (CG座標系: 左下原点, サイズ uprightWidth×uprightHeight)へ写す CTM を適用する。
    private static func applyOrientationTransform(
        _ orientation: CGImagePropertyOrientation,
        rawWidth: CGFloat,
        rawHeight: CGFloat,
        to context: CGContext
    ) {
        switch orientation {
        case .up:
            break
        case .upMirrored:
            context.translateBy(x: rawWidth, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .down:
            context.translateBy(x: rawWidth, y: rawHeight)
            context.rotate(by: .pi)
        case .downMirrored:
            context.translateBy(x: 0, y: rawHeight)
            context.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            context.translateBy(x: rawHeight, y: rawWidth)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: 1, y: -1)
        case .right:
            context.translateBy(x: 0, y: rawWidth)
            context.rotate(by: -.pi / 2)
        case .rightMirrored:
            context.rotate(by: .pi / 2)
            context.scaleBy(x: 1, y: -1)
        case .left:
            context.translateBy(x: rawHeight, y: 0)
            context.rotate(by: .pi / 2)
        }
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            outputData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return outputData as Data
    }
}
