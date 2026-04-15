import SwiftUI
import AppKit
import FloatingMacroCore

struct MacroButtonView: View {
    let button: ButtonDefinition
    let onTap: () -> Void

    @State private var isHovering = false

    /// Attempt to synthesize an icon. Priority:
    ///   1. explicit `icon` (file path / bundle id)
    ///   2. for a `.launch` action whose target looks like an app, infer
    ///      the app icon automatically
    private var inferredImage: NSImage? {
        if let img = IconLoader.image(for: button.icon) {
            return img
        }
        if case .launch(let target) = button.action {
            return IconLoader.image(for: target)
        }
        return nil
    }

    /// Parse `backgroundColor` hex string into a SwiftUI Color. nil = default.
    private var resolvedBackground: Color? {
        guard let hex = button.backgroundColor else { return nil }
        return Color(hex: hex)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if let img = inferredImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else if let iconText = button.iconText, !iconText.isEmpty {
                    Text(iconText)
                        .font(.system(size: 14))
                }
                Text(button.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundFill)
            )
        }
        .buttonStyle(.plain)
        .frame(width: button.width.map { CGFloat($0) },
               height: button.height.map { CGFloat($0) })
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundFill: Color {
        if let custom = resolvedBackground {
            return isHovering ? custom.opacity(0.75) : custom
        }
        return isHovering ? Color.accentColor.opacity(0.15) : Color.clear
    }
}

struct GroupView: View {
    let group: ButtonGroup
    let onButtonTap: (ButtonDefinition) -> Void

    @State private var collapsed: Bool

    init(group: ButtonGroup, onButtonTap: @escaping (ButtonDefinition) -> Void) {
        self.group = group
        self.onButtonTap = onButtonTap
        self._collapsed = State(initialValue: group.collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Group header
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text(group.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if !collapsed {
                ForEach(group.buttons, id: \.id) { btn in
                    MacroButtonView(button: btn) {
                        onButtonTap(btn)
                    }
                }
            }
        }
    }
}

struct PresetView: View {
    let preset: Preset
    let onButtonTap: (ButtonDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(preset.groups, id: \.id) { group in
                GroupView(group: group, onButtonTap: onButtonTap)
            }
        }
        .padding(8)
    }
}

// MARK: - Hex color helper

extension Color {
    /// Parse `#RRGGBB` or `#RRGGBBAA` (case insensitive, `#` optional).
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6 || str.count == 8,
              let value = UInt64(str, radix: 16) else {
            return nil
        }
        let r, g, b, a: Double
        if str.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >>  8) & 0xFF) / 255
            b = Double( value        & 0xFF) / 255
            a = 1.0
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >>  8) & 0xFF) / 255
            a = Double( value        & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, opacity: a)
    }
}
