import SafariServices
import SwiftUI

// MARK: Buttons

struct LargeButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .background(prominent ? Color.accentColor : Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LargeButtonStyle {
    static var large: LargeButtonStyle { LargeButtonStyle() }
    static var largeSecondary: LargeButtonStyle { LargeButtonStyle(prominent: false) }
}

struct ScaleOnPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: Icons

struct IconBadge: View {
    var systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: .rect(cornerRadius: size * 0.3))
    }
}

/// Settings row icon: white glyph on a colored rounded square.
struct SettingsIcon: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 7))
    }
}

struct SettingsRow<Trailing: View>: View {
    var icon: String
    var color: Color
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemName: icon, color: color)
            Text(title)
            Spacer()
            trailing.foregroundStyle(.secondary)
        }
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(icons, id: \.self) { icon in
                Button {
                    selection = icon
                    Haptics.tap()
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(selection == icon ? Color.white : Color.primary)
                        .background(selection == icon ? Color.accentColor : Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(ScaleOnPressStyle())
                .accessibilityLabel(icon)
            }
        }
    }
}

// MARK: Chips

struct Chip: View {
    var title: String
    var icon: String?
    var selected: Bool
    var suggested = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.footnote) }
                Text(title).font(.subheadline.weight(.medium))
                if suggested { Image(systemName: "sparkles").font(.caption2) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .capsule)
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color(.separator), lineWidth: 0.5))
        }
        .buttonStyle(ScaleOnPressStyle())
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

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
                label(Text(m), icon: AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)))
            case .failed(let m):
                label(Text(m), icon: AnyView(Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)))
            }
        }
        .animation(.spring, value: status)
    }

    private func label(_ text: Text, icon: AnyView) -> some View {
        HStack(spacing: 8) {
            icon
            text.font(.footnote.weight(.medium)).lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Shows the sync toast and auto-clears success messages.
    func syncToast() -> some View {
        modifier(SyncToastModifier())
    }

    func deleteConfirmation(_ title: String, message: String, isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
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
                SyncToast(status: sync.status).padding(.top, 4)
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
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
    }
}
