import AppKit
import SwiftUI
import FloatingMacroCore

/// Phase 5 (P5-9): Open window from menu bar "📱 Send to device".
///
/// display elements
/// Large QR code (embed Web Panel URL)
/// Text with the same URL (copyable)
/// LAN public mode on/off toggle (ControlAPIConfig.lanExposureEnabled)
/// "EphemeralLANTokenStore.rotate" button
///
/// When LAN OFF, display only the 'ON to' CTA without showing QR / URL. When LAN is
/// To enable ON, the ControlAPI must be enabled.
/// Guide to lead when disabled.
final class DeviceSendWindowController: NSWindowController {

    private let presetManager: PresetManager
    private let onLANToggle: (Bool) -> Void
    /// This window holds which preset it is currently being drawn for.
    /// Maintain the same preset during redraw when using LAN toggle and token rotation.
    /// AppDelegate.refreshDeviceSendWindowIfOpen reads.
    /// nil = menu via (= active preset's URL).
    private(set) var presetName: String?

    /// Lightweight ObservableObject. Regenerate on window opening.
    fileprivate final class Model: ObservableObject {
        @Published var lanExposed: Bool
        @Published var url: String
        @Published var qrPNG: Data?
        @Published var token: String
        @Published var bonjourReady: Bool
        /// Preset display name when displaying "This panel-specific QR" in the UI.
        /// If nil, output the current preset (active).
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
        window.title = L("Send to device 9efe2d")
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let view = DeviceSendView(model: model,
                                  onToggle: onLANToggle,
                                  onRotate: onRotate)
        window.contentView = NSHostingView(rootView: view)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Assuming the menu bar is called multiple times, reuse one window.
    /// Leave an API that allows updating the displayed content.
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

    /// Resolve the display name from the internal name in preset. If it cannot be loaded, return the internal name as-is.
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
                Text(L("Send to device 2d7f1e"))
                    .font(.title2).bold()
                Spacer()
                if let pd = model.presetDisplay {
                    Text(L_("preset_specific_qr", pd))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Current preset: 95367b"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // LAN public mode toggle. OFF to ON, QR appears.
            HStack {
                Toggle(L("LAN_Public mode_e6f2a7"),
                       isOn: Binding(get: { model.lanExposed },
                                     set: { onToggle($0) }))
                    .toggleStyle(.switch)
                Spacer()
                if model.lanExposed && model.bonjourReady {
                    Label(L("Bonjour_Public 36668c"), systemImage: "wifi")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if model.lanExposed {
                // QR code
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
                            Text(L("QR_Cannot generate _12ca69"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Copy URL text
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
                        Button(L("Copy 9e646d")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.url, forType: .string)
                        }
                    }
                }

                // reissue
                HStack {
                    Text("ephemeral token: \(String(model.token.prefix(8)))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Reissue_c126ef"), action: onRotate)
                }

                Text(L("LAN_Scan QR in Safari on iPhone/Tablet to open the URL above. Resend 220cce"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("LAN_Enabling public mode to _ON_ allows smartphones and tablets on the same Wi-Fi network to operate this panel f41a95."))
                        .font(.callout)
                    Text(L("OS_Will the firewall accept incoming connections for _FloatingMacro_ during initial activation? d8be95"))
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
