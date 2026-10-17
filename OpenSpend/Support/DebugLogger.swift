import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class DebugLogger {
    static let shared = DebugLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }

    private(set) var entries: [Entry] = []
    private let maxEntries = 500

    nonisolated func log(_ message: String) {
        #if DEBUG
        print("[OpenSpend] \(message)")
        #endif
        Task { @MainActor in
            entries.append(Entry(message: message))
            if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        }
    }

    func clear() { entries.removeAll() }
}

enum Haptics {
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    @MainActor static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
