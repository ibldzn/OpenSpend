import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A past expense offered while typing a title. Picking it fills the rest of the form.
struct TitleSuggestion: Identifiable, Hashable {
    var id: String { title.lowercased() }
    var title: String
    var amount: Double
    var currency: String
    var categories: [String]
    var payments: [String]
    var tags: [String]
}

/// Guesses category / payment method from an expense title.
///
/// Layer 1: an exact title seen before reuses its most frequent option.
/// Layer 2: the on-device Foundation model (iOS 26+, Apple Intelligence on).
/// Layer 3: sentence-embedding similarity against per-option prototypes.
@MainActor
final class SuggestionEngine {
    static let shared = SuggestionEngine()

    private struct Prototype { let name: String; let vector: [Double] }
    private var prototypeCache: [String: [Prototype]] = [:]
    // ponytail: fixed cosine threshold tuned by feel; make it adaptive if suggestions feel noisy.
    private let embeddingThreshold = 0.55

    // MARK: Titles

    func titleSuggestions(for text: String, in expenses: [Expense], limit: Int = 5) -> [TitleSuggestion] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        var seen = Set<String>()
        var out: [TitleSuggestion] = []
        for e in expenses where e.title.lowercased().hasPrefix(q) || e.title.lowercased().contains(" \(q)") {
            let key = e.title.lowercased()
            guard key != q, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(TitleSuggestion(title: e.title, amount: e.amount, currency: e.currency, categories: e.categories, payments: e.payments, tags: e.tags))
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Options

    func infer(_ kind: OptionKind, title: String, options: [String], history: [Expense], accountId: UUID) async -> String? {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !options.isEmpty else { return nil }
        let pick: (Expense) -> [String] = { kind == .category ? $0.categories : $0.payments }

        if let hit = historyMatch(title: title, options: options, history: history, pick: pick) {
            DebugLogger.shared.log("Smart Suggestions: history matched \(kind) \"\(hit)\" for \"\(title)\"")
            return hit
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let hit = await foundationModelMatch(kind, title: title, options: options) {
            DebugLogger.shared.log("Smart Suggestions: Foundation model matched \(kind) \"\(hit)\" for \"\(title)\"")
            return hit
        }
        #endif
        if let hit = embeddingMatch(kind, title: title, options: options, history: history, pick: pick, accountId: accountId) {
            DebugLogger.shared.log("Smart Suggestions: embedding matched \(kind) \"\(hit)\" for \"\(title)\"")
            return hit
        }
        DebugLogger.shared.log("Smart Suggestions: no \(kind) match for \"\(title)\"")
        return nil
    }

    private func historyMatch(title: String, options: [String], history: [Expense], pick: (Expense) -> [String]) -> String? {
        let key = title.lowercased()
        var counts: [String: Int] = [:]
        for e in history where e.title.lowercased() == key {
            for o in pick(e) where options.contains(o) { counts[o, default: 0] += 1 }
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private func embeddingMatch(_ kind: OptionKind, title: String, options: [String], history: [Expense],
                                pick: (Expense) -> [String], accountId: UUID) -> String? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let query = embedding.vector(for: title.lowercased()) else { return nil }

        // Prototype per option = mean vector of its name plus recent titles filed under it.
        let signature = "\(accountId)-\(kind)-\(options.joined(separator: "|"))-\(history.count)-\(history.first?.updatedAt.timeIntervalSince1970 ?? 0)"
        let prototypes: [Prototype]
        if let cached = prototypeCache[signature] {
            prototypes = cached
        } else {
            prototypes = options.compactMap { option in
                let texts = [option] + history.filter { pick($0).contains(option) }.prefix(20).map(\.title)
                let vectors = texts.compactMap { embedding.vector(for: $0.lowercased()) }
                guard let first = vectors.first else { return nil }
                var mean = [Double](repeating: 0, count: first.count)
                for v in vectors { for i in v.indices { mean[i] += v[i] / Double(vectors.count) } }
                return Prototype(name: option, vector: mean)
            }
            prototypeCache = [signature: prototypes]
        }

        let scored = prototypes.map { ($0.name, Self.cosine(query, $0.vector)) }.sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= embeddingThreshold else { return nil }
        return best.0
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na == 0 || nb == 0 ? 0 : dot / (na.squareRoot() * nb.squareRoot())
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func foundationModelMatch(_ kind: OptionKind, title: String, options: [String]) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let what = kind == .category ? "category that best describes this kind of merchant or purchase" : "payment method most likely used for this purchase"
        let session = LanguageModelSession(instructions: "You classify personal expenses. Pick the \(what) from the given list only.")
        let prompt = "Expense: \(title)\nOptions: \(options.joined(separator: ", "))"
        do {
            let r = try await session.respond(to: prompt, generating: InferredOption.self).content
            guard r.isConfident, let match = options.first(where: { $0.caseInsensitiveCompare(r.name) == .orderedSame }) else { return nil }
            return match
        } catch {
            DebugLogger.shared.log("Smart Suggestions: Foundation model error \(error.localizedDescription)")
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct InferredOption {
    @Guide(description: "The exact option name copied from the list, or an empty string if none clearly fits.")
    var name: String
    @Guide(description: "True only when the option is a strong match.")
    var isConfident: Bool
}
#endif
