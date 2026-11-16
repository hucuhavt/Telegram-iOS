import Foundation
import Postbox
import SwiftSignalKit
import AyuSettings

/// AyuGram "mark read after action": in ghost mode, sending a message in a chat
/// still marks that chat as read on the server (as AyuGram Desktop does).
func ayuMarkReadAfterAction(account: Account, peerId: PeerId) {
    let settings = AyuSettings.shared
    guard !settings.sendReadMessages, settings.markReadAfterAction else {
        return
    }
    settings.allowReadReceiptsBriefly()
    let _ = (synchronizePeerReadState(network: account.network, postbox: account.postbox, stateManager: account.stateManager, peerId: peerId, push: true, validate: false)
    |> `catch` { _ -> Signal<Never, NoError> in
        return .complete()
    }).startStandalone()
}

// MARK: - Saved media

/// Where a replay can copy attachments to: the account and its media cache.
struct AyuMediaContext {
    let accountPeerId: PeerId
    let mediaBox: MediaBox
}

private func ayuMediaPathExtension(file: TelegramMediaFile) -> String {
    if let fileName = file.fileName {
        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty {
            return ext
        }
    }
    let mimeType = file.mimeType.lowercased()
    if mimeType.hasPrefix("video/") {
        return "mp4"
    } else if mimeType == "audio/ogg" {
        return "ogg"
    } else if mimeType.hasPrefix("audio/") {
        return "m4a"
    } else if mimeType.hasPrefix("image/") {
        return mimeType == "image/png" ? "png" : "jpg"
    } else {
        return "bin"
    }
}

/// Downloaded files of a message's attachments (link previews left out).
private func ayuDownloadedMediaFiles(mediaBox: MediaBox, media: [Media]) -> [(path: String, pathExtension: String)] {
    var result: [(path: String, pathExtension: String)] = []
    for item in media {
        if let image = item as? TelegramMediaImage {
            if let representation = largestImageRepresentation(image.representations), let path = mediaBox.completedResourcePath(representation.resource) {
                result.append((path, "jpg"))
            }
        } else if let file = item as? TelegramMediaFile {
            if let path = mediaBox.completedResourcePath(file.resource) {
                result.append((path, ayuMediaPathExtension(file: file)))
            }
        }
    }
    return result
}

private func ayuAttachmentIds(_ media: [Media]) -> [MediaId] {
    return media.filter { !($0 is TelegramMediaWebpage) }.compactMap { $0.id }
}

// MARK: - Anti-recall

private func ayuShouldKeep(transaction: Transaction, id: MessageId) -> Bool {
    let settings = AyuSettings.shared
    guard settings.saveDeletedMessages else {
        return false
    }
    guard id.namespace == Namespaces.Message.Cloud else {
        return false
    }
    if !settings.saveForBots, let user = transaction.getPeer(id.peerId) as? TelegramUser, user.botInfo != nil {
        return false
    }
    return transaction.getMessage(id) != nil
}

/// Marks the messages a server deletion names as deleted instead of deleting them, and
/// copies their downloaded attachments when `mediaContext` is given.
/// Returns the ids that still have to be deleted for real.
func ayuKeepDeletedMessages(transaction: Transaction, ids: [MessageId], mediaContext: AyuMediaContext? = nil) -> [MessageId] {
    guard AyuSettings.shared.saveDeletedMessages else {
        return ids
    }
    let now = Int32(Date().timeIntervalSince1970)
    var remaining: [MessageId] = []
    for id in ids {
        if !ayuShouldKeep(transaction: transaction, id: id) {
            remaining.append(id)
            continue
        }
        transaction.updateMessage(id, update: { currentMessage in
            if currentMessage.ayuDeletedDate != nil {
                return .skip
            }
            if let mediaContext = mediaContext {
                let files = ayuDownloadedMediaFiles(mediaBox: mediaContext.mediaBox, media: currentMessage.media)
                let _ = AyuSavedMediaStore.shared.copy(accountId: mediaContext.accountPeerId.toInt64(), peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id, tag: "d", files: files)
            }
            var attributes = currentMessage.attributes
            attributes.append(AyuDeletedMessageAttribute(date: now))
            return .update(StoreMessage(updating: currentMessage, attributes: attributes, tags: currentMessage.tags))
        })
    }
    return remaining
}

/// The same for deletions that name messages by their global id (private chats and basic groups).
func ayuKeepDeletedMessages(transaction: Transaction, globalIds: [Int32], mediaContext: AyuMediaContext? = nil) -> [Int32] {
    guard AyuSettings.shared.saveDeletedMessages else {
        return globalIds
    }
    var remaining: [Int32] = []
    for globalId in globalIds {
        if let id = transaction.messageIdsForGlobalIds([globalId]).first {
            if ayuKeepDeletedMessages(transaction: transaction, ids: [id], mediaContext: mediaContext).isEmpty {
                continue
            }
        }
        remaining.append(globalId)
    }
    return remaining
}

/// Saved attachments of a message kept after deletion.
public func ayuDeletedMessageMedia(accountPeerId: EnginePeer.Id, messageId: EngineMessage.Id) -> [URL] {
    return AyuSavedMediaStore.shared.deletedMessageFiles(accountId: accountPeerId.toInt64(), peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
}

// MARK: - View-once / self-destructing media

/// Copies the downloaded attachments of a self-destructing (view-once/timer-based) message into the AyuGram cache
/// before the message is consumed or its media is replaced/cleaned up.
public func ayuSaveViewOnceMedia(accountPeerId: PeerId, postbox: Postbox, message: Message) -> [String] {
    let settings = AyuSettings.shared
    guard settings.saveViewOnceMedia, let timeout = message.minAutoremoveOrClearTimeout, timeout > 0 else {
        return []
    }
    let files = ayuDownloadedMediaFiles(mediaBox: postbox.mediaBox, media: message.media)
    let resources = ayuViewOnceMediaResources(message.media)
    guard !files.isEmpty, !resources.isEmpty, files.count == resources.count else {
        return []
    }
    return AyuSavedMediaStore.shared.copy(
        accountId: accountPeerId.toInt64(),
        peerId: message.id.peerId.toInt64(),
        namespace: message.id.namespace,
        id: message.id.id,
        tag: "v",
        files: files
    )
}

/// Full-size resources of a message's attachments that should be preserved for self-destructing media.
private func ayuViewOnceMediaResources(_ media: [Media]) -> [(media: Media, resource: MediaResource)] {
    var result: [(media: Media, resource: MediaResource)] = []
    for item in media {
        if let image = item as? TelegramMediaImage {
            if let representation = largestImageRepresentation(image.representations) {
                result.append((item, representation.resource))
            }
        } else if let file = item as? TelegramMediaFile {
            result.append((item, file.resource))
        }
    }
    return result
}

/// Downloads a self-destructing (view-once/timer-based) message's attachments in the background and copies them into
/// the AyuGram cache as soon as each one is complete, so the copy exists before the
/// message is consumed, expires, or its media is replaced/cleaned up.
func ayuTrackViewOnceMedia(accountPeerId: PeerId, postbox: Postbox, message: Message) {
    guard AyuSettings.shared.saveViewOnceMedia, let timeout = message.minAutoremoveOrClearTimeout, timeout > 0 else {
        return
    }
    let _ = ayuSaveViewOnceMedia(accountPeerId: accountPeerId, postbox: postbox, message: message)
    let messageReference = MessageReference(message)
    for (media, resource) in ayuViewOnceMediaResources(message.media) {
        let userContentType: MediaResourceUserContentType
        if let file = media as? TelegramMediaFile {
            userContentType = MediaResourceUserContentType(file: file)
        } else {
            userContentType = .image
        }
        let _ = fetchedMediaResource(
            mediaBox: postbox.mediaBox,
            userLocation: .peer(message.id.peerId),
            userContentType: userContentType,
            reference: .media(media: .message(message: messageReference, media: media), resource: resource)
        ).start(completed: {
            let _ = ayuSaveViewOnceMedia(accountPeerId: accountPeerId, postbox: postbox, message: message)
        })
    }
}

/// Called when a media resource finishes downloading: if it belongs to a self-destructing
/// (view-once/timer-based) message, copy the message's attachments.
func ayuViewOnceMediaFetchCompleted(accountPeerId: PeerId, postbox: Postbox, reference: MediaResourceReference) {
    guard AyuSettings.shared.saveViewOnceMedia else {
        return
    }
    guard case let .media(mediaReference, _) = reference, case let .message(messageReference, _) = mediaReference, let id = messageReference.id else {
        return
    }
    let _ = postbox.transaction { transaction -> Void in
        guard let message = transaction.getMessage(id) else {
            return
        }
        let _ = ayuSaveViewOnceMedia(accountPeerId: accountPeerId, postbox: postbox, message: message)
    }.start()
}

/// Attachments copied from a view-once message.
public func ayuViewOnceMessageMedia(accountPeerId: EnginePeer.Id, messageId: EngineMessage.Id) -> [URL] {
    return AyuSavedMediaStore.shared.viewOnceMessageFiles(
        accountId: accountPeerId.toInt64(),
        peerId: messageId.peerId.toInt64(),
        namespace: messageId.namespace,
        id: messageId.id
    )
}

// MARK: - Edit history

/// Saves the text (and downloaded attachments) a message had before a server edit replaces it.
func ayuRecordEdit(mediaContext: AyuMediaContext, previous: Message, updated: StoreMessage) {
    let settings = AyuSettings.shared
    guard settings.saveMessagesHistory else {
        return
    }
    guard previous.id.namespace == Namespaces.Message.Cloud else {
        return
    }
    let previousAttachments = ayuAttachmentIds(previous.media)
    let textChanged = previous.text != updated.text
    let mediaChanged = !previousAttachments.isEmpty && previousAttachments != ayuAttachmentIds(updated.media)
    guard textChanged || mediaChanged else {
        return
    }
    if !settings.saveForBots, let user = previous.peers[previous.id.peerId] as? TelegramUser, user.botInfo != nil {
        return
    }
    let date = previous.editedTime ?? previous.timestamp
    let accountId = mediaContext.accountPeerId.toInt64()
    var mediaFiles: [String]?
    if mediaChanged {
        let files = ayuDownloadedMediaFiles(mediaBox: mediaContext.mediaBox, media: previous.media)
        let names = AyuSavedMediaStore.shared.copy(accountId: accountId, peerId: previous.id.peerId.toInt64(), namespace: previous.id.namespace, id: previous.id.id, tag: "e\(date)", files: files)
        if !names.isEmpty {
            mediaFiles = names
        }
    }
    AyuEditHistoryStore.shared.append(
        accountId: accountId,
        peerId: previous.id.peerId.toInt64(),
        namespace: previous.id.namespace,
        id: previous.id.id,
        entry: AyuEditHistoryEntry(text: previous.text, date: date, mediaFiles: mediaFiles)
    )
}

/// Previous versions of a message, oldest first.
public func ayuEditHistory(accountPeerId: EnginePeer.Id, messageId: EngineMessage.Id) -> [AyuEditHistoryEntry] {
    return AyuEditHistoryStore.shared.entries(
        accountId: accountPeerId.toInt64(),
        peerId: messageId.peerId.toInt64(),
        namespace: messageId.namespace,
        id: messageId.id
    )
}

/// A saved attachment of an earlier version of a message.
public func ayuSavedMediaUrl(accountPeerId: EnginePeer.Id, name: String) -> URL? {
    return AyuSavedMediaStore.shared.url(accountId: accountPeerId.toInt64(), name: name)
}
