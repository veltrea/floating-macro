import AppKit
import SwiftUI
import FloatingMacroCore

/// Phase 5 (P5-9): メニューバー「📱 デバイスに送信」から開く小窓。
///
/// 表示要素:
///   - 大きな QR コード (Web Panel URL を埋め込み)
///   - 同じ URL のテキスト (コピーできる)
///   - LAN 公開モードの ON/OFF トグル (= ControlAPIConfig.lanExposureEnabled)
///   - 「再発行」ボタン (= EphemeralLANTokenStore.rotate)
///
/// LAN OFF のときは QR / URL を出さず、「ON にする」CTA だけ出す。LAN を
/// ON にするには ControlAPI が enabled でなければならないので、ControlAPI が
/// disabled のときも CTA で誘導する。
final class DeviceSendWindowController: NSWindowController {

    private let presetManager: PresetManager
    private let onLANToggle: (Bool) -> Void
    /// 「このウィンドウは現在どの preset 用に描画されているか」を保持する。
    /// LAN トグル / token rotate での再描画時に同じ preset を維持するために
    /// AppDelegate.refreshDeviceSendWindowIfOpen が読み取る。
    /// nil = メニュー経由 (= active preset の URL)。
    private(set) var presetName: String?

    /// 軽量な ObservableObject。ウィンドウを開くたびに再生成する。
    fileprivate final class Model: ObservableObject {
        @Published var lanExposed: Bool
        @Published var url: String
        @Published var qrPNG: Data?
        @Published var token: String
        @Published var bonjourReady: Bool
        /// UI に「このパネル専用 QR」と表示するときの preset 表示名。
        /// nil なら「現在のプリセット (active)」を出す。
        @Published var presetDisplay: String?

        init(lanExposed: Bool, url: String, qrPNG: Data?, token: String,
             bonjourReady: Bool, presetDisplay: String?) {
            self.lanExposed = lanExposed
            self.url = url
            self.qrPNG = qrPNG
            self.token = token
            self.bonjourReady = bonjourReady
            self.presetDisplay = presetDisplay
        }
    }

    private let model: Model

    init(presetManager: PresetManager,
         lanExposed: Bool,
         url: String,
         qrPNG: Data?,
         token: String,
         bonjourReady: Bool,
         presetName: String?,
         onLANToggle: @escaping (Bool) -> Void,
         onRotate: @escaping () -> Void) {
        self.presetManager = presetManager
        self.onLANToggle = onLANToggle
        self.presetName = presetName
        let presetDisplay = Self.resolveDisplay(presetManager: presetManager, presetName: presetName)
        let model = Model(lanExposed: lanExposed, url: url,
                          qrPNG: qrPNG, token: token, bonjourReady: bonjourReady,
                          presetDisplay: presetDisplay)
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("デバイスに送信_9efe2d")
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let view = DeviceSendView(model: model,
                                  onToggle: onLANToggle,
                                  onRotate: onRotate)
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// メニューバーから複数回呼ばれても 1 つのウィンドウを再利用する想定で、
    /// 表示内容を更新できる API を出しておく。
    func update(lanExposed: Bool, url: String, qrPNG: Data?, token: String,
                bonjourReady: Bool, presetName: String?) {
        self.presetName = presetName
        model.lanExposed = lanExposed
        model.url = url
        model.qrPNG = qrPNG
        model.token = token
        model.bonjourReady = bonjourReady
        model.presetDisplay = Self.resolveDisplay(presetManager: presetManager,
                                                  presetName: presetName)
    }

    /// preset 内部名から UI 表示名を解決する。読み込めなかった場合は内部名をそのまま返す。
    fileprivate static func resolveDisplay(presetManager: PresetManager,
                                           presetName: String?) -> String? {
        guard let name = presetName else { return nil }
        if let p = presetManager.preset(named: name) { return p.displayName }
        return name
    }
}

// MARK: - SwiftUI

private struct DeviceSendView: View {
    @ObservedObject var model: DeviceSendWindowController.Model
    let onToggle: (Bool) -> Void
    let onRotate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("デバイスに送信_2d7f1e"))
                    .font(.title2).bold()
                Spacer()
                if let pd = model.presetDisplay {
                    Text(L_("preset_specific_qr", pd))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("現在のプリセット_95367b"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // LAN 公開モード トグル。OFF→ON で QR が現れる。
            HStack {
                Toggle(L("LAN_公開モード_e6f2a7"),
                       isOn: Binding(get: { model.lanExposed },
                                     set: { onToggle($0) }))
                    .toggleStyle(.switch)
                Spacer()
                if model.lanExposed && model.bonjourReady {
                    Label(L("Bonjour_公開中_36668c"), systemImage: "wifi")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if model.lanExposed {
                // QR コード
                Group {
                    if let png = model.qrPNG, let nsImage = NSImage(data: png) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 320, height: 320)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(8)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 320, height: 320)
                            Text(L("QR_を生成できません_12ca69"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // URL テキスト + コピー
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(model.url)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        Button(L("コピー_9e646d")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.url, forType: .string)
                        }
                    }
                }

                // Token 再発行
                HStack {
                    Text("ephemeral token: \(String(model.token.prefix(8)))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("再発行_c126ef"), action: onRotate)
                }

                Text(L("LAN_内のスマホ_タブレットの_Safari_で_QR_を読むと_上の_URL_が開きます_再発行_220cce"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("LAN_公開モードを_ON_にすると_同じ_Wi_Fi_にいるスマホ_タブレットからこのパネルを操作_f41a95"))
                        .font(.callout)
                    Text(L("OS_のファイアウォールが初回有効化時に_FloatingMacro_が着信接続を受け付けるか_を聞_d8be95"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 460, height: 580, alignment: .topLeading)
    }
}
