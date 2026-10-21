import SafariServices
import SwiftUI

// MARK: Backdrop & surfaces

/// Flat backdrop used behind every screen.
struct AppBackground: View {
    var body: some View {
        Palette.background
            .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Gives a List/Form/ScrollView screen the shared backdrop.
    func appScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground())
    }

    /// Flat card surface with a hairline border.
    func card(padding: CGFloat = Space.lg, radius: CGFloat = Radius.lg) -> some View {
        self.padding(padding)
            .background(Palette.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.border, lineWidth: 1))
    }

    /// Fades and lifts content in, staggered by `index`. Skipped under Reduce Motion.
    func staggeredAppear(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(Motion.enter.delay(Double(min(index, 8)) * 0.05)) { shown = true }
            }
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Palette.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Buttons

struct LargeButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(prominent ? Palette.onPrimary : Palette.primary)
            .background(prominent ? Palette.cta : Palette.fill, in: .rect(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(prominent ? Color.clear : Palette.border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LargeButtonStyle {
    static var large: LargeButtonStyle { LargeButtonStyle() }
    static var largeSecondary: LargeButtonStyle { LargeButtonStyle(prominent: false) }
}

/// Press feedback without changing layout bounds.
struct ScaleOnPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 44pt circular icon button for top bars.
struct CircleIconButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Palette.surface, in: .circle)
                .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
        }
        .buttonStyle(ScaleOnPressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: Icons

struct IconBadge: View {
    var systemName: String
    var tint: Color = Palette.primary
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Palette.fill, in: .rect(cornerRadius: size * 0.28))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28).strokeBorder(Palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Settings row icon: glyph on a neutral tile. `color` is ignored in the monochrome theme.
struct SettingsIcon: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.primary)
            .frame(width: 30, height: 30)
            .background(Palette.fill, in: .rect(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

struct SettingsRow<Trailing: View>: View {
    var icon: String
    var color: Color
    var title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: Space.md) {
            SettingsIcon(systemName: icon, color: color)
            // Trailing value drops under the title at accessibility sizes so words don't hyphenate.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    trailing.foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            } else {
                Text(title)
                Spacer()
                trailing.foregroundStyle(Palette.textMuted)
            }
        }
        .frame(minHeight: 36)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(icon: String, color: Color, title: String) {
        self.init(icon: icon, color: color, title: title) { EmptyView() }
    }
}

struct IconGridView: View {
    var icons: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.sm), count: 6), spacing: Space.sm) {
            ForEach(icons, id: \.self) { icon in
                let selected = selection == icon
                Button {
                    withAnimation(Motion.select) { selection = icon }
                    Haptics.tap()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(selected ? Palette.onPrimary : Palette.primary)
                        .background(selected ? Palette.primary : Palette.fill, in: .rect(cornerRadius: Radius.sm))
                }
                .buttonStyle(ScaleOnPressStyle())
                .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: Chips & pills

struct Chip: View {
    var title: String
    var icon: String?
    var selected: Bool
    var suggested = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.footnote.weight(.semibold)) }
                Text(title).font(.subheadline.weight(.medium)).lineLimit(1)
                if suggested {
                    Image(systemName: "sparkles").font(.caption2.weight(.bold))
                        .accessibilityLabel("Suggested")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .foregroundStyle(selected ? Palette.onPrimary : Palette.primary)
            .background(selected ? Palette.primary : Palette.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.border, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(ScaleOnPressStyle())
        .animation(Motion.select, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Single-choice segmented pills with a sliding selection.
struct PillPicker<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(options, id: \.self) { option in
                let on = option == selection
                Button {
                    withAnimation(Motion.select) { selection = option }
                    Haptics.tap()
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .foregroundStyle(on ? Palette.onPrimary : Palette.textMuted)
                        .background {
                            if on { Capsule().fill(Palette.primary).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.xs)
        .background(Palette.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        // Compact segmented control: capped like system tab bars so labels never truncate.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for row in rows {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var y: CGFloat; var height: CGFloat; var items: [(Int, CGFloat)] }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !current.items.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append((i, x))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: Sync toast

struct SyncToast: View {
    var status: ExpenseSyncService.Status

    var body: some View {
        Group {
            switch status {
            case .idle:
                EmptyView()
            case .syncing(let name):
                label(Text("Syncing \(name)…"), icon: AnyView(ProgressView().controlSize(.small)))
            case .success(let m):
                label(Text(m), icon: AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)))
            case .failed(let m):
                label(Text(m), icon: AnyView(Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)))
            }
        }
        .animation(Motion.enter, value: status)
    }

    private func label(_ text: Text, icon: AnyView) -> some View {
        HStack(spacing: Space.sm) {
            icon
            text.font(.footnote.weight(.semibold)).lineLimit(2)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(Palette.surface, in: .capsule)
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Shows the sync toast and auto-clears success messages.
    func syncToast() -> some View {
        modifier(SyncToastModifier())
    }

    func deleteConfirmation(_ title: String, message: String, isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        alert(title, isPresented: isPresented) {
            Button("Delete", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

private struct SyncToastModifier: ViewModifier {
    @State private var sync = ExpenseSyncService.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                SyncToast(status: sync.status).padding(.top, Space.xs)
            }
            .task(id: sync.status) {
                let delay: Double
                switch sync.status {
                case .success: delay = 2
                case .failed: delay = 4
                default: return
                }
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled { sync.status = .idle }
            }
    }
}

// MARK: Safari

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 64, height: 64)
                .background(Palette.fill, in: .circle)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Palette.textMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
        .accessibilityElement(children: .combine)
    }
}
