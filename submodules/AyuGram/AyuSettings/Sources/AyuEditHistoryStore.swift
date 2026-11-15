import Foundation

/// One previous version of an edited message.
public struct AyuEditHistoryEntry: Codable, Equatable {
    /// Text before the edit.
    public let text: String
    /// When that version was posted or last edited (unix time).
    public let date: Int32

    public init(text: String, date: Int32) {
        self.text = text
        self.date = date
    }
}

/// Previous versions of edited messages, kept outside Postbox.
///
/// Telegram rewrites a stored message whole when it refetches history, which would drop
/// anything kept in the message itself, so AyuGram (like AyuGram Desktop with its own
/// database) keeps the history in its own files: one JSON file per message under
/// Application Support/ayugram/edit-history/<account>/.
public final class AyuEditHistoryStore: @unchecked Sendable {
    public static let shared = AyuEditHistoryStore()

    private let queue = DispatchQueue(label: "ayugram.edit-history")
    private let baseUrl: URL?

    init() {
        if let supportUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.baseUrl = supportUrl.appendingPathComponent("ayugram/edit-history", isDirectory: true)
        } else {
            self.baseUrl = nil
        }
    }

    private func fileUrl(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> URL? {
        return self.baseUrl?
            .appendingPathComponent("\(accountId)", isDirectory: true)
            .appendingPathComponent("\(peerId)_\(namespace)_\(id).json", isDirectory: false)
    }

    private func read(_ url: URL) -> [AyuEditHistoryEntry] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder().decode([AyuEditHistoryEntry].self, from: data)) ?? []
    }

    /// Appends a previous version; repeated identical versions are skipped.
    public func append(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32, entry: AyuEditHistoryEntry) {
        guard let url = self.fileUrl(accountId: accountId, peerId: peerId, namespace: namespace, id: id) else {
            return
        }
        self.queue.async {
            var entries = self.read(url)
            if entries.last?.text == entry.text {
                return
            }
            entries.append(entry)
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(entries)
                try data.write(to: url, options: .atomic)
            } catch {
            }
        }
    }

    /// Previous versions, oldest first.
    public func entries(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> [AyuEditHistoryEntry] {
        guard let url = self.fileUrl(accountId: accountId, peerId: peerId, namespace: namespace, id: id) else {
            return []
        }
        return self.queue.sync {
            return self.read(url)
        }
    }

    public func hasEntries(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> Bool {
        guard let url = self.fileUrl(accountId: accountId, peerId: peerId, namespace: namespace, id: id) else {
            return false
        }
        return self.queue.sync {
            return FileManager.default.fileExists(atPath: url.path)
        }
    }
}
