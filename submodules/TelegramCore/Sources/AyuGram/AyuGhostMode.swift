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
