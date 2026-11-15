//
//  ScuffsPlugin.swift
//  Sleeves
//
//  プラグイン「スカッフ(擦りキズ)」。
//  ジャケット表面の髪の毛状の細い擦り傷と、白い斑点状の
//  すり傷を再現する。実物では暗いジャケットで特に目立つ。
//

import SwiftUI
import os

struct ScuffsPlugin: ShelfPlugin {

    private static let logger = Logger(
        subsystem: "com.cacheandbuffer.Sleeves", category: "Plugins")

    /// パラメータID。PluginState.valuesの永続化キーになるので
    /// 一度決めたら変更しない(変えると保存済みの値が効かなくなる)
    private enum Param {
        /// 線傷(hairline)の量・密度(0〜3、1=従来の最大)
        static let hairline = "hairline"
        /// 斑点(speckles)の量・密度(0〜3、1=従来の最大)
        static let speckles = "speckles"
    }

    /// デフォルトの線傷の量
    static let defaultHairline: Double = 0.4
    /// デフォルトの斑点の量
    static let defaultSpeckles: Double = 0.4
    /// 量パラメータの範囲。1.0=従来の最大密度で、
    /// 上限3.0まで効きを強められる(値=密度倍率として線形に効く)
    private static let amountRange: ClosedRange<Double> = 0...3

    let id = "scuffs"
    let displayName = "Scuffs"
    let category: ShelfPluginCategory = .record

    init() {
        Self.logger.info("plugin registered: scuffs ('Scuffs')")
    }

    var parameterSpecs: [PluginParameterSpec] {
        [
            .slider(.init(
                id: Param.hairline,
                label: "Hairline",
                range: Self.amountRange,
                step: 0.01,
                defaultValue: Self.defaultHairline
            )),
            .slider(.init(
                id: Param.speckles,
                label: "Speckles",
                range: Self.amountRange,
                step: 0.01,
                defaultValue: Self.defaultSpeckles
            )),
        ]
    }

    // MARK: - (b) ジャケットへのオーバーレイ重畳

    /// 実効量がこれ以下ならオーバーレイ自体を返さない閾値。
    /// 肉眼でほぼ見えない傷の描画コストを省く下限(P8-4)
    private static let minEffectiveAmount: Double = 0.005

    /// 線傷(hairline)の疑似乱数saltの基点。
    /// 傷iのパラメータは salt = base + i*saltsPerLine + k の連番で取る
    private static let saltHairline: Double = 100
    /// 線傷1本が消費するsalt数(中心x,y・stray判定・長さ・湾曲・
    /// 線幅・濃さ・色味・向きのk=0-8に加え、太傷抽選・色味バリアント・
    /// ハロー・2本組・分割数・伴線長のk=9-17を使用。余裕持たせて20とする。
    /// 最大42本でも 100+41*20+19=939 で斑点基点1000未満に収まる)
    private static let saltsPerLine: Double = 20

    /// 斑点(speckles)の疑似乱数saltの基点。
    /// クラスタcのパラメータは salt = base + c*saltsPerCluster + …
    private static let saltSpeckle: Double = 1000
    /// 斑点クラスタ1個が消費するsalt数。
    /// ヘッダはk=0-9を使用(k0-4は従来のエリア選択・中心x,y・半径・
    /// 点数、k5-9は擦れ面の有無・濃さ・大きさ・縦横比・回転)。
    /// 点は+10から各16個×最大10点=160、ヘッダと合わせて最大170。
    /// 余裕を持たせて200とする(最大18クラスタでも
    /// 1000+17*200+169=4569。なお5000以降はEdgeWearPluginが
    /// 色味用に使うので、今後saltを広げるならそれを避ける)
    private static let saltsPerCluster: Double = 200
    /// クラスタの点1個が消費するsalt数。
    /// k=0-3は従来通り(角度・半径・径・濃さ)。実物の斑点が
    /// 「均一な白い真円の集まり」ではないのを再現するため
    /// k=4-13で点ごとの変化を引く(k14-15は予約):
    ///   k4  大きめ斑点の抽選(prominent。径と濃さを同じ抽選にして
    ///       大きい点=目立つ点に相関させる — 線傷のprominentと同じ考え方)
    ///   k5  ごく小さい点の抽選
    ///   k6  色味の白さ(白系の帯内位置)
    ///   k7  色味バリアントの抽選(白以外の点)
    ///   k8  バリアント種別と帯内位置
    ///   k9  形の抽選(真円/楕円/短いスジ傷)
    ///   k10 楕円の縦横比
    ///   k11 楕円・スジ傷の回転角
    ///   k12 ハロー(にじみ)の有無
    ///   k13 スジ傷の長さ
    private static let saltsPerSpeckleDot: Double = 16

    /// 線傷の基準本数(hairline=1=従来の最大・密度係数1のセル)。
    /// 実物は数本〜十数本で、量パラメータとセルごとの
    /// 密度係数(0.4〜1.0)を掛ける(hairline=3で最大42本)
    private static let maxLines: Double = 14
    /// 斑点クラスタの基準個数(speckles=1・密度係数1のセル。
    /// speckles=3で最大18個)
    private static let maxClusters: Double = 6
    /// クラスタ内の斑点の個数範囲(実物は小さな点の集まり)
    private static let dotsPerCluster: ClosedRange<Int> = 3...10

    /// 線傷の長さ(セル一辺に対する割合)の範囲。実物の
    /// ヘアライン傷はセルのかなりの部分を横切る長いものが多い
    private static let lineLengthRange: ClosedRange<Double> = 0.12...0.55
    /// 線傷の線幅(pt)の範囲。髪の毛状なので細め
    private static let lineWidthRange: ClosedRange<Double> = 0.4...1.2
    /// 少数派の太めの傷の線幅(pt)の範囲。実物には時折、
    /// 爪や機材で付いたような一本太い擦り傷が混ざる
    private static let thickLineWidthRange: ClosedRange<Double> = 1.5...2.5
    /// 太めの傷が混ざる確率(目安10〜15%。大半は従来の細さを維持する)
    private static let prominentLineRate: Double = 0.12
    /// 線傷の不透明度の範囲。実物は繊細で主張しすぎない
    /// (濃さはpowで淡い側に偏らせる — 大半はうっすら、ごく一部だけ見える)
    private static let lineOpacityRange: ClosedRange<Double> = 0.05...0.2
    /// 少数派のはっきり見える傷の不透明度の範囲。
    /// 実物で太い傷は目立つので、線幅と同じprominent抽選で
    /// 濃さも上げて相関させる(別々に引くと太いのに薄い不自然な傷が出る)
    private static let strongLineOpacityRange: ClosedRange<Double> = 0.25...0.4
    /// 線傷がセルごとの主方向から外れる確率。
    /// 実物の傷はおおむね同じ向きだが、少量の外れ傷が混ざる
    private static let strayLineRate: Double = 0.18
    /// 主方向に沿う傷の角度ばらつき(±rad、約17°)。
    /// 完全平行だと機械的に見えるので緩く揺らす
    private static let angleJitter: Double = 0.3
    /// 線傷の弧の湾曲の最大値(長さに対する割合)。
    /// 制御点を法線方向へずらす量で、0=直線
    private static let maxLineBend: Double = 0.3

    /// 白以外の色味の傷が混ざる確率。実物は紙の擦れや埃で
    /// 白一色ではない傷も付く(くすんだグレー・薄い暖色・暗い痕)
    private static let colorVariantRate: Double = 0.18
    /// ハロー(にじみ)を持つ傷の確率。明るい芯線の下に幅広・
    /// 低不透明度のstrokeを重ねて、擦れた跡のにじみを出す
    private static let haloLineRate: Double = 0.15
    /// ハローの芯線に対する線幅倍率
    private static let haloWidthFactor: Double = 3.5
    /// ハローの芯線に対する不透明度倍率(にじみなので淡く)
    private static let haloOpacityFactor: Double = 0.35
    /// 平行な2本組の傷になる確率。実物の傷は束で付くことがある
    private static let pairedLineRate: Double = 0.12
    /// 2本組の間隔(pt)の範囲。近すぎると1本の太傷に見える
    private static let pairOffsetRange: ClosedRange<Double> = 2...6
    /// 2本目(伴線)の長さ係数の範囲。本線より短い方が
    /// 擦れ始め・終わりのずれが出て自然に見える
    private static let pairLengthFactorRange: ClosedRange<Double> = 0.5...0.9
    /// 2本目の線幅・不透明度の係数(主線より細く淡い従線にする)
    private static let pairWidthFactor: Double = 0.6
    private static let pairOpacityFactor: Double = 0.8
    /// 線傷を端に向かって細く薄くするための分割セグメント数。
    /// trimmedPathで部分パスを切り出し、包絡線を掛けて個別strokeする
    /// (実物の擦り傷は両端が先細りに消える。均一な太さの線より自然)
    private static let taperSegmentRange: ClosedRange<Int> = 3...7
    /// セグメント端部の最小線幅スケール。包絡線は端0→中央1だが
    /// 0だと端が完全に消えて線が短く見えるので下限を持たせる
    private static let taperMinWidthScale: Double = 0.4

    /// 斑点クラスタが集まる「すれ跡エリア」の広がり
    /// (セル一辺に対する割合)。実物の斑点は全面一様ではなく、
    /// 棚や手が触れる場所に集中して付く
    private static let focalSpread: Double = 0.2
    /// 斑点クラスタの広がり半径(セル一辺に対する割合)の範囲
    private static let clusterSpreadRange: ClosedRange<Double> = 0.03...0.12
    /// 斑点1個の径(pt)の範囲(実物は1〜3ptの小さな点が大半)
    private static let speckleSizeRange: ClosedRange<Double> = 1...3
    /// 斑点の不透明度の範囲。白いすり傷だが淡く保つ
    private static let speckleOpacityRange: ClosedRange<Double> = 0.06...0.25
    /// 大半の斑点の不透明度を淡い側に偏らせる指数。
    /// 範囲は変えずに分布だけうっすら側へ寄せる(線傷と同じ流儀)
    private static let speckleOpacityBias: Double = 1.3
    /// 大きめ斑点が混ざる確率(目安10〜15%)。実物のすり傷には
    /// 時折ひと回り大きな点が混ざる。大きい点は目立つので
    /// 濃さも同じ抽選で上げて相関させる(線傷のprominentと同じ考え方。
    /// 別々に引くと大きいのに薄い不自然な点が出る)
    private static let largeSpeckleRate: Double = 0.12
    /// 大きめ斑点の径(pt)の範囲
    private static let largeSpeckleSizeRange: ClosedRange<Double> = 3...6
    /// 大きめ斑点の不透明度の範囲(ごく少数のはっきり見える点)
    private static let strongSpeckleOpacityRange: ClosedRange<Double> = 0.3...0.45
    /// ごく小さい点が混ざる確率。擦れの粉っぽい細かさを出す
    private static let tinySpeckleRate: Double = 0.2
    /// ごく小さい点の径(pt)の範囲(1pt未満も混ぜる)
    private static let tinySpeckleSizeRange: ClosedRange<Double> = 0.4...1
    /// 縦横比のある楕円の斑点が混ざる確率。
    /// 実物の斑点は擦れ方向に少し伸びた形も混ざる
    private static let ellipseSpeckleRate: Double = 0.18
    /// 短いスジ状の傷が混ざる確率(ごく少数。
    /// 点状ではなく数ptの擦れ筋として付く実物の傷)
    private static let streakSpeckleRate: Double = 0.07
    /// 楕円斑点の縦横比の範囲。真円に近い側を多めにするため控えめ
    private static let ellipseAspectRange: ClosedRange<Double> = 1.3...2.4
    /// スジ傷の長さ(pt)の範囲
    private static let streakLengthRange: ClosedRange<Double> = 3...8
    /// スジ傷の太さ(斑点の径に対する係数。上限を掛けて
    /// 大きめ斑点から太いスジが出ないようにする)
    private static let streakWidthFactor: Double = 0.35
    /// ハロー(にじみ)を持つ斑点の確率。芯の下に同形を
    /// 拡大した薄いfillを敷いて、擦れた面の柔らかい滲みを出す
    private static let speckleHaloRate: Double = 0.25
    /// ハローの芯に対する径倍率
    private static let speckleHaloFactor: Double = 2.2
    /// ハローの芯に対する不透明度倍率(にじみなので淡く)
    private static let speckleHaloOpacityFactor: Double = 0.3
    /// クラスタの下に「擦れ面」(クラスタ広がり程度の
    /// ごく薄い楕円)を敷く確率。点群を「擦れた領域の上の傷」
    /// として読ませる。全部に敷くと面の主張が強いので一部にする
    private static let speckleSurfaceRate: Double = 0.7
    /// 擦れ面の不透明度の範囲。点よりさらに淡く、
    /// 面としてかろうじて感知できる程度に抑える
    private static let speckleSurfaceOpacityRange: ClosedRange<Double> = 0.03...0.08
    /// 擦れ面の半径係数の範囲(クラスタ広がり半径に対する倍率)
    private static let speckleSurfaceScaleRange: ClosedRange<Double> = 0.7...1.1
    /// 擦れ面の縦横比の範囲(擦れ方向へ少し伸びた面にする)
    private static let speckleSurfaceAspectRange: ClosedRange<Double> = 1.0...1.5
    /// クラスタ内の点の半径分布の偏り指数。
    /// sqrt(=円盤一様)から指数>1の分布に変えて中心寄りに偏らせる
    /// (外縁にまばら・中心に密、が実物のすり傷に近い)
    private static let clusterRadiusBias: Double = 1.6

    /// セルごとの密度係数の範囲。実物は傷の量が盤ごとに
    /// 偏るので、量パラメータが同じでもセルによって傷の多寡をつける
    private static let densityFactorRange: ClosedRange<Double> = 0.4...1.0

    func jacketOverlay(context: ShelfPluginContext) -> AnyView? {
        let hairline = resolvedAmount(
            Param.hairline, default: Self.defaultHairline, context: context)
        let speckles = resolvedAmount(
            Param.speckles, default: Self.defaultSpeckles, context: context)
        // 実効量≈0の種類は傷なし扱いで描画コストを省く。
        // 両方≈0ならオーバーレイ自体を返さない
        // (無効時と同じく描画・ヒットの影響ゼロにする)
        let lineCount = hairline > Self.minEffectiveAmount
            ? lineCount(amount: hairline, context: context) : 0
        let clusterCount = speckles > Self.minEffectiveAmount
            ? clusterCount(amount: speckles, context: context) : 0
        // 傷が1つも無いセルでは空のCanvasを積まずオーバーレイを返さない
        guard lineCount > 0 || clusterCount > 0 else { return nil }
        // ログの量は設定値そのまま(セルごとの本数は参考情報)
        logAppliedOnce(hairline: hairline, speckles: speckles,
                       lines: lineCount, clusters: clusterCount)

        return AnyView(
            Canvas { gc, size in
                // ゼロサイズでは傷の長さが0で除算がNaNになるので抜ける
                guard size.width > 0, size.height > 0 else { return }
                if lineCount > 0 {
                    self.drawHairlines(&gc, size: size, count: lineCount,
                                       context: context)
                }
                if clusterCount > 0 {
                    self.drawSpeckles(&gc, size: size, count: clusterCount,
                                      context: context)
                }
            }
            // オーバーレイがジャケットのタップ再生・D&D・右クリックの
            // ヒット判定を食わないようにする
            .allowsHitTesting(false)
        )
    }

    // MARK: - オーバーレイ描画

    /// (a) 髪の毛状の細い淡い線傷をcount本描く。
    /// 1本は二次ベジェの弧(湾曲が小さいほど直線に見える)。
    /// 傷iのsalt基点は saltHairline + i*saltsPerLine で、
    /// そこから連番で中心・向き・長さ・湾曲・線幅・濃さ・色味を引く
    /// (決定論的: 同じセルでは再描画・再起動でも同じ傷になる)。
    /// 向きはセルごとの主方向±angleJitterに揃える(実物はスリーブへの
    /// 出し入れ等で同じ向きに傷が付くため。strayLineRateの割合だけ
    /// 向きの違う外れ傷を混ぜる)。salt 50/60帯はセル単位の
    /// 主方向・集中エリア用に確保(線傷salt基点は100から)
    ///
    /// k=0-8は従来通り(位置・向き・長さ・湾曲・線幅・濃さ・色味)。
    /// 実物の傷が「均一な細い白線」ではないのを再現するため
    /// k=9-17で傷ごとの変化を引く:
    ///   k9  少数の太くはっきりした傷の抽選(prominent。
    ///       線幅と濃さを同じ抽選にして太い傷=目立つ傷に相関させる)
    ///   k10 色味バリアントの抽選(白以外の傷)
    ///   k11 バリアント種別と帯内位置
    ///   k12 ハロー(にじみ)の有無
    ///   k13 平行な2本組の傷の有無
    ///   k14 2本目のオフセット量
    ///   k15 2本目を置く側(±)
    ///   k16 テーパー分割セグメント数
    ///   k17 2本目の長さ係数
    private func drawHairlines(_ gc: inout GraphicsContext, size: CGSize,
                               count: Int, context: ShelfPluginContext) {
        // セルごとの傷の主方向(0〜π。傷に表裏はないので軸として扱う)
        let main = hash01(50, context: context) * .pi
        for i in 0..<count {
            let base = Self.saltHairline + Double(i) * Self.saltsPerLine
            func r(_ k: Double) -> Double {
                hash01(base + k, context: context)
            }
            let cx = r(0) * size.width
            let cy = r(1) * size.height
            let angle = r(2) < Self.strayLineRate
                ? r(8) * .pi
                : main + (r(8) * 2 - 1) * Self.angleJitter
            let len = Self.lineLengthRange.lerp(r(3)) * size.width
            // 制御点を法線方向へずらす量(長さの±maxLineBendまでの緩い弧)
            let bend = (r(4) * 2 - 1) * len * Self.maxLineBend
            let path = scuffPath(cx: cx, cy: cy, angle: angle,
                                 len: len, bend: bend)
            let prominent = r(9) < Self.prominentLineRate
            let width = prominent
                ? Self.thickLineWidthRange.lerp(r(5))
                : Self.lineWidthRange.lerp(r(5))
            let opacity = prominent
                ? Self.strongLineOpacityRange.lerp(pow(r(6), 1.5))
                : Self.lineOpacityRange.lerp(pow(r(6), 1.5))
            let color = lineColor(whiteness: r(7), roll: r(10),
                                  variant: r(11))
            let segments = Self.taperSegmentRange.lowerBound
                + Int(r(16) * Double(Self.taperSegmentRange.upperBound
                                     - Self.taperSegmentRange.lowerBound + 1))
            // ハローは芯線より先(下)に引く。同じ包絡線で端も
            // 薄くなるよう strokeTapered を共用する
            if r(12) < Self.haloLineRate {
                strokeTapered(&gc, path: path, color: color,
                              width: width * Self.haloWidthFactor,
                              opacity: opacity * Self.haloOpacityFactor,
                              segments: segments)
            }
            strokeTapered(&gc, path: path, color: color,
                          width: width, opacity: opacity,
                          segments: segments)
            // 平行な伴線: 主線と同じ向きのまま法線方向へ数ptずらし、
            // 短め細めにする(実物の傷は束で付くことがある)
            if r(13) < Self.pairedLineRate {
                let side = r(15) < 0.5 ? -1.0 : 1.0
                let off = Self.pairOffsetRange.lerp(r(14)) * side
                let plen = len * Self.pairLengthFactorRange.lerp(r(17))
                // 伴線の湾曲は主線と同じ向き・長さ比例にして
                // ほぼ平行な弧になるようにする
                let pbend = (r(4) * 2 - 1) * plen * Self.maxLineBend
                let nx = -sin(angle)
                let ny = cos(angle)
                let ppath = scuffPath(cx: cx + nx * off,
                                      cy: cy + ny * off,
                                      angle: angle, len: plen,
                                      bend: pbend)
                strokeTapered(&gc, path: ppath, color: color,
                              width: width * Self.pairWidthFactor,
                              opacity: opacity * Self.pairOpacityFactor,
                              segments: max(Self.taperSegmentRange.lowerBound,
                                            segments - 1))
            }
        }
    }

    /// 中心(cx,cy)・向きangle・長さlenの二次ベジェ弧のPath。
    /// 端点は中心から向き方向へ半長ずつ、制御点は法線方向へbendずらす
    private func scuffPath(cx: Double, cy: Double, angle: Double,
                           len: Double, bend: Double) -> Path {
        let dx = cos(angle) * len * 0.5
        let dy = sin(angle) * len * 0.5
        var path = Path()
        path.move(to: CGPoint(x: cx - dx, y: cy - dy))
        path.addQuadCurve(
            to: CGPoint(x: cx + dx, y: cy + dy),
            control: CGPoint(x: cx - dy / (len * 0.5) * bend,
                             y: cy + dx / (len * 0.5) * bend)
        )
        return path
    }

    /// 1本の線傷を、端に向かって細く薄くなるよう分割してstrokeする。
    /// trimmedPathで部分パスを切り出し、セグメント中点の位置から
    /// 端0→中央1の包絡線(sinカーブで滑らかに立ち上がる)を求め、
    /// 不透明度と線幅をスケールして個別にstrokeする
    private func strokeTapered(_ gc: inout GraphicsContext, path: Path,
                               color: Color, width: Double,
                               opacity: Double, segments: Int) {
        for s in 0..<segments {
            let t0 = Double(s) / Double(segments)
            let t1 = Double(s + 1) / Double(segments)
            let env = sin(.pi * (t0 + t1) * 0.5)
            gc.stroke(
                path.trimmedPath(from: t0, to: t1),
                with: .color(color.opacity(opacity * env)),
                lineWidth: width * (Self.taperMinWidthScale
                                    + (1 - Self.taperMinWidthScale) * env)
            )
        }
    }

    /// 線傷の色。大半は白〜淡いグレー(紙色が透けて見えるすり傷の近似)。
    /// roll < colorVariantRate の少数だけ別の色味にする。
    /// variant(0〜1)を3帯に割って、種別と帯内位置uを同じ値から取る
    /// (別saltを増やさずに種別と明度のばらつきを両立させる)
    private func lineColor(whiteness w: Double, roll: Double,
                           variant v: Double) -> Color {
        guard roll < Self.colorVariantRate else {
            // 従来通りの白系(0.85〜1.0)
            return Color(white: 0.85 + 0.15 * w)
        }
        let sv = v * 3
        let u = sv - sv.rounded(.down)
        switch min(Int(sv), 2) {
        case 0:
            // ややくすんだグレー(墨っぽい擦れ)
            return Color(white: 0.6 + 0.2 * u)
        case 1:
            // ごく薄い暖色(紙の擦れ・埃っぽさ。彩度は控えめに)
            return Color(hue: 0.08 + 0.04 * u, saturation: 0.12,
                         brightness: 0.8 + 0.15 * u)
        default:
            // わずかに暗い擦れ跡(明るいジャケット上で見える痕)
            return Color(white: 0.3 + 0.15 * u)
        }
    }

    /// (b) 白い斑点状のすり傷をcountクラスタ分描く。
    /// 1クラスタは中心+広がり半径を持つ小さな点群で、
    /// クラスタcのsalt基点は saltSpeckle + c*saltsPerCluster。
    /// ヘッダ(k0-4: エリア選択・中心x,y・半径・点数、k5-9: 擦れ面)
    /// を引き、点dには 10 + d*saltsPerSpeckleDot から連番で角度・
    /// 半径・径・濃さ・大きさ抽選・色味・形・ハローを引く
    /// (salt設計の内訳はsaltsPerSpeckleDotのコメント参照)。
    /// クラスタ中心は全面一様ではなく、セルごとの「すれ跡エリア」
    /// (1〜3箇所、salt 60帯)の周辺±focalSpreadに集まる — 実物は
    /// 棚や手が触れる場所に斑点が集中する。
    /// 点は大半が従来通りの1〜3ptの淡い白点だが、少数に大きめ
    /// 濃いめの点・ごく小さい点・色味の違う点・楕円や短いスジ傷・
    /// ハロー付きを混ぜ、クラスタ内分布は中心寄りに偏らせる。
    /// またクラスタの一部の下にごく薄い「擦れ面」を敷き、
    /// 点群を擦れた領域の上の傷として読ませる
    private func drawSpeckles(_ gc: inout GraphicsContext, size: CGSize,
                              count: Int, context: ShelfPluginContext) {
        // セルごとのすれ跡エリア数(1〜3箇所)
        let focalCount = 1 + Int(hash01(60, context: context) * 2.99)
        for c in 0..<count {
            let base = Self.saltSpeckle + Double(c) * Self.saltsPerCluster
            func r(_ k: Double) -> Double {
                hash01(base + k, context: context)
            }
            // どのすれ跡エリアに属するかを選び、そのエリア中心の
            // 周辺にクラスタを置く(エリア内で重なって密度差が出る)
            let f = Int(r(0) * Double(focalCount))
            let fx = (0.1 + 0.8 * hash01(61 + Double(f) * 13,
                                        context: context)) * size.width
            let fy = (0.1 + 0.8 * hash01(61 + Double(f) * 13 + 1,
                                        context: context)) * size.height
            let cx = fx + (r(1) * 2 - 1) * Self.focalSpread * size.width
            let cy = fy + (r(2) * 2 - 1) * Self.focalSpread * size.height
            let spread = Self.clusterSpreadRange.lerp(r(3)) * size.width
            let dots = Self.dotsPerCluster.lowerBound
                + Int(r(4) * Double(Self.dotsPerCluster.upperBound
                                    - Self.dotsPerCluster.lowerBound + 1))
            // 擦れ面: 点群の下に敷くごく薄い楕円。点より先(下)に引く。
            // 少し縦横比を持たせて回転させ、擦れ方向に延びた跡にする
            if r(5) < Self.speckleSurfaceRate {
                let sOpacity = Self.speckleSurfaceOpacityRange.lerp(r(6))
                let w = spread * 2 * Self.speckleSurfaceScaleRange.lerp(r(7))
                let h = w / Self.speckleSurfaceAspectRange.lerp(r(8))
                var t = CGAffineTransform(translationX: cx, y: cy)
                t = t.rotated(by: r(9) * .pi)
                gc.fill(
                    Path(ellipseIn: CGRect(x: -w * 0.5, y: -h * 0.5,
                                           width: w, height: h))
                        .applying(t),
                    with: .color(.white.opacity(sOpacity))
                )
            }
            for d in 0..<dots {
                let db = base + 10 + Double(d) * Self.saltsPerSpeckleDot
                func rd(_ k: Double) -> Double {
                    hash01(db + k, context: context)
                }
                let a = rd(0) * 2 * .pi
                // powで指数>1にして中心寄りに偏る分布にする
                // (円盤一様のsqrtでは外縁まで均一で、実物より均質に見える)
                let dist = pow(rd(1), Self.clusterRadiusBias) * spread
                let px = cx + cos(a) * dist
                let py = cy + sin(a) * dist
                // 大きめ斑点と濃さを同じ抽選にして相関させる
                let prominent = rd(4) < Self.largeSpeckleRate
                // 大きめでない点の一部だけごく小さい点にする
                let tiny = !prominent && rd(5) < Self.tinySpeckleRate
                let dot = prominent
                    ? Self.largeSpeckleSizeRange.lerp(rd(2))
                    : tiny
                        ? Self.tinySpeckleSizeRange.lerp(rd(2))
                        : Self.speckleSizeRange.lerp(rd(2))
                let opacity = prominent
                    ? Self.strongSpeckleOpacityRange.lerp(rd(3))
                    : Self.speckleOpacityRange.lerp(
                        pow(rd(3), Self.speckleOpacityBias))
                // 色味は線傷と同じlineColorを共用する
                // (大半は白系、少数にくすんだグレー・薄い暖色・暗い点)
                let color = lineColor(whiteness: rd(6), roll: rd(7),
                                      variant: rd(8))
                let shape = rd(9)
                if shape < Self.streakSpeckleRate {
                    // 短いスジ状の傷。数ptの先細りの線で、線傷と
                    // 同じstrokeTaperedで両端を消す(湾曲なしの直線)
                    let slen = Self.streakLengthRange.lerp(rd(13))
                    let sw = min(1.0, max(0.4, dot * Self.streakWidthFactor))
                    strokeTapered(
                        &gc,
                        path: scuffPath(cx: px, cy: py,
                                        angle: rd(11) * .pi,
                                        len: slen, bend: 0),
                        color: color, width: sw, opacity: opacity,
                        segments: 3)
                    continue
                }
                // 真円/楕円の斑点パス。楕円は縦横比を持たせて回転する
                let dotPath: Path
                if shape < Self.streakSpeckleRate + Self.ellipseSpeckleRate {
                    let h = dot / Self.ellipseAspectRange.lerp(rd(10))
                    var t = CGAffineTransform(translationX: px, y: py)
                    t = t.rotated(by: rd(11) * .pi)
                    dotPath = Path(ellipseIn: CGRect(
                        x: -dot * 0.5, y: -h * 0.5,
                        width: dot, height: h)).applying(t)
                } else {
                    dotPath = Path(ellipseIn: CGRect(
                        x: px - dot * 0.5, y: py - dot * 0.5,
                        width: dot, height: dot))
                }
                // ハローは芯より先(下)に引く。芯と同形をその場で
                // 拡大した薄いfillで、擦れの滲みを出す
                if rd(12) < Self.speckleHaloRate {
                    let ht = CGAffineTransform(translationX: px, y: py)
                        .scaledBy(x: Self.speckleHaloFactor,
                                  y: Self.speckleHaloFactor)
                        .translatedBy(x: -px, y: -py)
                    gc.fill(
                        dotPath.applying(ht),
                        with: .color(color.opacity(
                            opacity * Self.speckleHaloOpacityFactor))
                    )
                }
                gc.fill(dotPath, with: .color(color.opacity(opacity)))
            }
        }
    }

    // MARK: - パラメータ解決

    /// 量パラメータをspec範囲(0〜3)にクランプして解決する
    private func resolvedAmount(_ id: String, default fallback: Double,
                                context: ShelfPluginContext) -> Double {
        min(Self.amountRange.upperBound,
            max(Self.amountRange.lowerBound,
                context.number(id, default: fallback)))
    }

    /// セルごとの密度係数(0.4〜1.0)。同じamountでもセルによって
    /// 傷の量に差が出るようにする。kindで線傷/斑点を独立に引く
    private func densityFactor(_ kind: Double,
                               context: ShelfPluginContext) -> Double {
        let r = Self.densityFactorRange
        return r.lowerBound + (r.upperBound - r.lowerBound)
            * hash01(kind, context: context)
    }

    /// 線傷の本数。amountに比例し、セルごとの密度係数でばらつく
    private func lineCount(amount: Double,
                           context: ShelfPluginContext) -> Int {
        Int((Self.maxLines * amount
            * densityFactor(1, context: context)).rounded())
    }

    /// 斑点クラスタの個数。amountに比例し、セルごとの密度係数でばらつく
    private func clusterCount(amount: Double,
                              context: ShelfPluginContext) -> Int {
        Int((Self.maxClusters * amount
            * densityFactor(2, context: context)).rounded())
    }

    /// セル座標からの決定論的疑似乱数(0〜1)。同じセルでは
    /// 再描画・リロード・リブートを経ても同じ値になる
    /// (sinハッシュ。乱数生成器や状態の保持はしない)。
    /// saltは同一セルから複数の独立した値を取るための種
    private func hash01(_ salt: Double, context: ShelfPluginContext) -> Double {
        let seed = context.cellCenter.x * 127.1
            + context.cellCenter.y * 311.7
            + salt * 74.7
        let v = sin(seed) * 43758.5453123
        return v - v.rounded(.down)
    }

    /// プロセス内で最初の1回だけ解決値を記録する
    /// (セル描画のたびに呼ばれるので、毎回ログは出さない。
    ///  有効/無効とパラメータ確定のログはSettingsView側が出す)
    private static var didLogApplied = false
    private func logAppliedOnce(hairline: Double, speckles: Double,
                                lines: Int, clusters: Int) {
        guard !Self.didLogApplied else { return }
        Self.didLogApplied = true
        Self.logger.notice("scuffs applied: hairline=\(hairline, privacy: .public) speckles=\(speckles, privacy: .public) lines=\(lines, privacy: .public) clusters=\(clusters, privacy: .public)")
    }
}

private extension ClosedRange where Bound == Double {
    /// 範囲の両端の間をt(0〜1)で線形補間する
    func lerp(_ t: Double) -> Double {
        lowerBound + (upperBound - lowerBound) * t
    }
}
