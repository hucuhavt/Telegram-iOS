import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import AyuSettings

/// Emits once immediately and again after every AyuGram settings change.
public func ayuSettingsUpdates() -> Signal<Void, NoError> {
    return Signal { subscriber in
        subscriber.putNext(Void())
        let observer = NotificationCenter.default.addObserver(forName: AyuSettings.didChangeNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(Void())
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private final class AyuGramSettingsArguments {
    let update: (AyuGramSettingsToggle, Bool) -> Void

    init(update: @escaping (AyuGramSettingsToggle, Bool) -> Void) {
        self.update = update
    }
}

enum AyuGramSettingsToggle: Int32 {
    case ghostMode
    case sendReadMessages
    case sendReadStories
    case sendOnlinePackets
    case sendUploadProgress
    case sendOfflinePacketAfterOnline
    case markReadAfterAction
    case saveDeletedMessages
    case saveMessagesHistory
    case saveForBots
    case disableCopyRestrictions
}

private enum AyuGramSettingsSection: Int32 {
    case ghost
    case ghostDetails
    case spy
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case ghostHeader
    case ghostMode(Bool)
    case ghostFooter

    case detailsHeader
    case toggle(AyuGramSettingsToggle, String, Bool)
    case detailsFooter

    case spyHeader
    case spyToggle(AyuGramSettingsToggle, String, Bool)
    case spyFooter

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMode, .ghostFooter:
            return AyuGramSettingsSection.ghost.rawValue
        case .detailsHeader, .toggle, .detailsFooter:
            return AyuGramSettingsSection.ghostDetails.rawValue
        case .spyHeader, .spyToggle, .spyFooter:
            return AyuGramSettingsSection.spy.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader:
            return 0
        case .ghostMode:
            return 1
        case .ghostFooter:
            return 2
        case .detailsHeader:
            return 10
        case let .toggle(toggle, _, _):
            return 11 + toggle.rawValue
        case .detailsFooter:
            return 100
        case .spyHeader:
            return 200
        case let .spyToggle(toggle, _, _):
            return 201 + toggle.rawValue
        case .spyFooter:
            return 300
        }
    }

    static func <(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        switch self {
        case .ghostHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "РЕЖИМ ПРИЗРАКА", sectionId: self.section)
        case let .ghostMode(value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "Режим призрака", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(.ghostMode, value)
            })
        case .ghostFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Собеседники не увидят, что вы прочитали сообщения, просмотрели истории, были в сети или печатаете."), sectionId: self.section)
        case .detailsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАСТРОЙКА", sectionId: self.section)
        case let .toggle(toggle, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(toggle, value)
            })
        case .detailsFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Читать после действия»: когда вы отправляете сообщение, чат отмечается прочитанным даже в режиме призрака."), sectionId: self.section)
        case .spyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ШПИОНСКИЕ ФУНКЦИИ", sectionId: self.section)
        case let .spyToggle(toggle, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(toggle, value)
            })
        case .spyFooter:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Удалённые собеседником сообщения остаются в чате с пометкой 🧹. Прошлые версии отредактированных сообщений доступны в меню сообщения → «История изменений». «Обходить запрет копирования» разрешает копировать текст, сохранять фото, видео и файлы и делать скриншоты в чатах и каналах, где это запрещено. Пересылка таких сообщений всё равно запрещена сервером."), sectionId: self.section)
        }
    }
}

private func ayuGramSettingsEntries(settings: AyuSettings) -> [AyuGramSettingsEntry] {
    var entries: [AyuGramSettingsEntry] = []
    entries.append(.ghostHeader)
    entries.append(.ghostMode(settings.isGhostModeActive))
    entries.append(.ghostFooter)

    entries.append(.detailsHeader)
    entries.append(.toggle(.sendReadMessages, "Отправлять «прочитано»", settings.sendReadMessages))
    entries.append(.toggle(.sendReadStories, "Отправлять просмотр историй", settings.sendReadStories))
    entries.append(.toggle(.sendOnlinePackets, "Отправлять «в сети»", settings.sendOnlinePackets))
    entries.append(.toggle(.sendUploadProgress, "Отправлять «печатает»", settings.sendUploadProgress))
    entries.append(.toggle(.sendOfflinePacketAfterOnline, "Отправлять «не в сети»", settings.sendOfflinePacketAfterOnline))
    entries.append(.toggle(.markReadAfterAction, "Читать после действия", settings.markReadAfterAction))
    entries.append(.detailsFooter)

    entries.append(.spyHeader)
    entries.append(.spyToggle(.saveDeletedMessages, "Сохранять удалённые сообщения", settings.saveDeletedMessages))
    entries.append(.spyToggle(.saveMessagesHistory, "Сохранять историю изменений", settings.saveMessagesHistory))
    entries.append(.spyToggle(.saveForBots, "Сохранять в чатах с ботами", settings.saveForBots))
    entries.append(.spyToggle(.disableCopyRestrictions, "Обходить запрет копирования", settings.disableCopyRestrictions))
    entries.append(.spyFooter)
    return entries
}

public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    let settings = AyuSettings.shared

    let arguments = AyuGramSettingsArguments(update: { toggle, value in
        switch toggle {
        case .ghostMode:
            settings.setGhostModeActive(value)
        case .sendReadMessages:
            settings.sendReadMessages = value
        case .sendReadStories:
            settings.sendReadStories = value
        case .sendOnlinePackets:
            settings.sendOnlinePackets = value
        case .sendUploadProgress:
            settings.sendUploadProgress = value
        case .sendOfflinePacketAfterOnline:
            settings.sendOfflinePacketAfterOnline = value
        case .markReadAfterAction:
            settings.markReadAfterAction = value
        case .saveDeletedMessages:
            settings.saveDeletedMessages = value
        case .saveMessagesHistory:
            settings.saveMessagesHistory = value
        case .saveForBots:
            settings.saveForBots = value
        case .disableCopyRestrictions:
            settings.disableCopyRestrictions = value
        }
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        ayuSettingsUpdates()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuGramSettingsEntries(settings: settings), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    return controller
}
