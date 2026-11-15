import Foundation

/// AyuGram settings, stored in the app's own UserDefaults.
///
/// Mirrors `AyuSettings` from AyuGramDesktop (`Telegram/SourceFiles/ayu/ayu_settings.h`).
/// Reads are thread-safe (UserDefaults is), so TelegramCore can consult them from any queue.
public final class AyuSettings: @unchecked Sendable {
    public static let shared = AyuSettings()

    /// Posted on the main queue after any setting changes.
    public static let didChangeNotification = Notification.Name("AyuSettingsDidChange")

    private let defaults: UserDefaults
    private let prefix = "ayugram."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func bool(_ key: String, _ defaultValue: Bool) -> Bool {
        return self.defaults.object(forKey: self.prefix + key) as? Bool ?? defaultValue
    }

    private func setBool(_ key: String, _ value: Bool) {
        self.defaults.set(value, forKey: self.prefix + key)
        self.notifyChanged()
    }

    private func notifyChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: AyuSettings.didChangeNotification, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: AyuSettings.didChangeNotification, object: self)
            }
        }
    }

    private func string(_ key: String, _ defaultValue: String) -> String {
        return self.defaults.string(forKey: self.prefix + key) ?? defaultValue
    }

    private func setString(_ key: String, _ value: String) {
        self.defaults.set(value, forKey: self.prefix + key)
        self.notifyChanged()
    }

    // MARK: - Anti-recall and message history

    /// Keep messages that others delete, marked as deleted.
    public var saveDeletedMessages: Bool {
        get { return self.bool("saveDeletedMessages", true) }
        set { self.setBool("saveDeletedMessages", newValue) }
    }

    /// Keep previous versions of edited messages.
    public var saveMessagesHistory: Bool {
        get { return self.bool("saveMessagesHistory", true) }
        set { self.setBool("saveMessagesHistory", newValue) }
    }

    /// Also keep deleted and edited messages in chats with bots.
    public var saveForBots: Bool {
        get { return self.bool("saveForBots", false) }
        set { self.setBool("saveForBots", newValue) }
    }

    /// Mark shown next to the time of a deleted message.
    public var deletedMark: String {
        get { return self.string("deletedMark", "🧹") }
        set { self.setString("deletedMark", newValue) }
    }

    /// Draw deleted messages semi-transparent.
    public var semiTransparentDeletedMessages: Bool {
        get { return self.bool("semiTransparentDeletedMessages", false) }
        set { self.setBool("semiTransparentDeletedMessages", newValue) }
    }

    // MARK: - Ghost mode

    /// Send read receipts for messages (messages.readHistory and friends).
    public var sendReadMessages: Bool {
        get { return self.bool("sendReadMessages", true) }
        set { self.setBool("sendReadMessages", newValue) }
    }

    /// Mark stories as viewed on the server.
    public var sendReadStories: Bool {
        get { return self.bool("sendReadStories", true) }
        set { self.setBool("sendReadStories", newValue) }
    }

    /// Send the "online" status.
    public var sendOnlinePackets: Bool {
        get { return self.bool("sendOnlinePackets", true) }
        set { self.setBool("sendOnlinePackets", newValue) }
    }

    /// Send "typing…" / "uploading…" activity.
    public var sendUploadProgress: Bool {
        get { return self.bool("sendUploadProgress", true) }
        set { self.setBool("sendUploadProgress", newValue) }
    }

    /// Send an "offline" status right after the app would go online.
    public var sendOfflinePacketAfterOnline: Bool {
        get { return self.bool("sendOfflinePacketAfterOnline", false) }
        set { self.setBool("sendOfflinePacketAfterOnline", newValue) }
    }

    /// Mark a chat as read after sending a message or reacting in it, even in ghost mode.
    public var markReadAfterAction: Bool {
        get { return self.bool("markReadAfterAction", true) }
        set { self.setBool("markReadAfterAction", newValue) }
    }

    /// Show the ghost mode switch in the chat list.
    public var showGhostToggleInChatList: Bool {
        get { return self.bool("showGhostToggleInChatList", true) }
        set { self.setBool("showGhostToggleInChatList", newValue) }
    }

    /// Ghost mode is on when every "send" option is off (same rule as AyuGram Desktop).
    public var isGhostModeActive: Bool {
        return !self.sendReadMessages
            && !self.sendReadStories
            && !self.sendOnlinePackets
            && !self.sendUploadProgress
            && self.sendOfflinePacketAfterOnline
    }

    public func setGhostModeActive(_ active: Bool) {
        self.defaults.set(!active, forKey: self.prefix + "sendReadMessages")
        self.defaults.set(!active, forKey: self.prefix + "sendReadStories")
        self.defaults.set(!active, forKey: self.prefix + "sendOnlinePackets")
        self.defaults.set(!active, forKey: self.prefix + "sendUploadProgress")
        self.defaults.set(active, forKey: self.prefix + "sendOfflinePacketAfterOnline")
        self.notifyChanged()
    }

    // MARK: - Temporary read bypass

    private let bypassLock = NSLock()
    private var readBypassUntil: Double = 0.0

    /// Lets read receipts through for a short moment, used by "mark read after action".
    public func allowReadReceiptsBriefly(seconds: Double = 3.0) {
        self.bypassLock.lock()
        self.readBypassUntil = Date().timeIntervalSince1970 + seconds
        self.bypassLock.unlock()
    }

    private var isReadBypassActive: Bool {
        self.bypassLock.lock()
        defer { self.bypassLock.unlock() }
        return Date().timeIntervalSince1970 < self.readBypassUntil
    }

    // MARK: - Network filter

    private static let readMessageRequests: Set<String> = [
        "messages.readHistory",
        "channels.readHistory",
        "messages.readDiscussion",
        "messages.readSavedHistory",
        "messages.readEncryptedHistory",
        "messages.readMessageContents",
        "channels.readMessageContents",
    ]

    private static let readStoryRequests: Set<String> = [
        "stories.readStories",
        "stories.incrementStoryViews",
    ]

    private static let activityRequests: Set<String> = [
        "messages.setTyping",
        "messages.setEncryptedTyping",
    ]

    /// Whether a request with this TL function name must not reach the server.
    public func shouldBlockRequest(functionName name: String) -> Bool {
        if AyuSettings.readMessageRequests.contains(name) {
            return !self.sendReadMessages && !self.isReadBypassActive
        }
        if AyuSettings.readStoryRequests.contains(name) {
            return !self.sendReadStories
        }
        if AyuSettings.activityRequests.contains(name) {
            return !self.sendUploadProgress
        }
        return false
    }
}
