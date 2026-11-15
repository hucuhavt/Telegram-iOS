import Foundation

/// Copies of attachments AyuGram keeps for deleted and edited messages, so they survive
/// Telegram's cache cleanup. Files live in Application Support/ayugram/media/<account>/.
public final class AyuSavedMediaStore: @unchecked Sendable {
    public static let shared = AyuSavedMediaStore()

    private let queue = DispatchQueue(label: "ayugram.saved-media", qos: .utility)
    private let baseUrl: URL?

    init() {
        if let supportUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            self.baseUrl = supportUrl.appendingPathComponent("ayugram/media", isDirectory: true)
        } else {
            self.baseUrl = nil
        }
    }

    private func directory(accountId: Int64) -> URL? {
        return self.baseUrl?.appendingPathComponent("\(accountId)", isDirectory: true)
    }

    private static func prefix(peerId: Int64, namespace: Int32, id: Int32) -> String {
        return "\(peerId)_\(namespace)_\(id)_"
    }

    /// Copies files in the background and returns the names they will have.
    /// `tag` tells copies of one message apart ("d" for deleted, "e<date>" for an edit).
    public func copy(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32, tag: String, files: [(path: String, pathExtension: String)]) -> [String] {
        guard let directory = self.directory(accountId: accountId), !files.isEmpty else {
            return []
        }
        var names: [String] = []
        var copies: [(String, URL)] = []
        for (index, file) in files.enumerated() {
            let ext = file.pathExtension.isEmpty ? "bin" : file.pathExtension
            let name = AyuSavedMediaStore.prefix(peerId: peerId, namespace: namespace, id: id) + "\(tag)_\(index).\(ext)"
            names.append(name)
            copies.append((file.path, directory.appendingPathComponent(name)))
        }
        self.queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (source, destination) in copies {
                if FileManager.default.fileExists(atPath: destination.path) {
                    continue
                }
                try? FileManager.default.copyItem(atPath: source, toPath: destination.path)
            }
        }
        return names
    }

    public func url(accountId: Int64, name: String) -> URL? {
        guard let url = self.directory(accountId: accountId)?.appendingPathComponent(name) else {
            return nil
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saved attachments of a message kept after deletion.
    public func deletedMessageFiles(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> [URL] {
        return self.messageFiles(accountId: accountId, peerId: peerId, namespace: namespace, id: id, tag: "d")
    }

    /// Saved attachments of a view-once message.
    public func viewOnceMessageFiles(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32) -> [URL] {
        return self.messageFiles(accountId: accountId, peerId: peerId, namespace: namespace, id: id, tag: "v")
    }

    public func messageFiles(accountId: Int64, peerId: Int64, namespace: Int32, id: Int32, tag: String) -> [URL] {
        guard let directory = self.directory(accountId: accountId) else {
            return []
        }
        let prefix = AyuSavedMediaStore.prefix(peerId: peerId, namespace: namespace, id: id) + "\(tag)_"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { directory.appendingPathComponent($0) }
    }
}
