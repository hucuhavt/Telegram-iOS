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

/// Marks the messages a server deletion names as deleted instead of deleting them.
/// Returns the ids that still have to be deleted for real.
func ayuKeepDeletedMessages(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
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
            var attributes = currentMessage.attributes
            attributes.append(AyuDeletedMessageAttribute(date: now))
            return .update(StoreMessage(updating: currentMessage, attributes: attributes, tags: currentMessage.tags))
        })
    }
    return remaining
}

/// The same for deletions that name messages by their global id (private chats and basic groups).
func ayuKeepDeletedMessages(transaction: Transaction, globalIds: [Int32]) -> [Int32] {
    guard AyuSettings.shared.saveDeletedMessages else {
        return globalIds
    }
    var remaining: [Int32] = []
    for globalId in globalIds {
        if let id = transaction.messageIdsForGlobalIds([globalId]).first {
            if ayuKeepDeletedMessages(transaction: transaction, ids: [id]).isEmpty {
                continue
            }
        }
        remaining.append(globalId)
    }
    return remaining
}

// MARK: - Edit history

/// Saves the text a message had before a server edit replaces it.
func ayuRecordEdit(accountPeerId: PeerId, previous: Message, updatedText: String) {
    let settings = AyuSettings.shared
    guard settings.saveMessagesHistory, previous.text != updatedText, !previous.text.isEmpty else {
        return
    }
    guard previous.id.namespace == Namespaces.Message.Cloud else {
        return
    }
    if !settings.saveForBots, let user = previous.peers[previous.id.peerId] as? TelegramUser, user.botInfo != nil {
        return
    }
    let date = previous.editedTime ?? previous.timestamp
    AyuEditHistoryStore.shared.append(
        accountId: accountPeerId.toInt64(),
        peerId: previous.id.peerId.toInt64(),
        namespace: previous.id.namespace,
        id: previous.id.id,
        entry: AyuEditHistoryEntry(text: previous.text, date: date)
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
