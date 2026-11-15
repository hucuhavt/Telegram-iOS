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
    let clearHiddenUsers: () -> Void

    init(update: @escaping (AyuGramSettingsToggle, Bool) -> Void, clearHiddenUsers: @escaping () -> Void) {
        self.update = update
        self.clearHiddenUsers = clearHiddenUsers
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
    case saveViewOnceMedia
    case disableCopyRestrictions
    case disableAds
    case showPeerId
    case streamerMode
}

private enum AyuGramSettingsSection: Int32 {
    case ghost
    case ghostDetails
    case history
    case other
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case header(section: AyuGramSettingsSection, id: Int32, text: String)
    case footer(section: AyuGramSettingsSection, id: Int32, text: String)
    case toggle(section: AyuGramSettingsSection, toggle: AyuGramSettingsToggle, title: String, value: Bool)
    case clearHiddenUsers(count: Int)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _, _), let .footer(section, _, _), let .toggle(section, _, _, _):
            return section.rawValue
        case .clearHiddenUsers:
            return AyuGramSettingsSection.other.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(_, id, _), let .footer(_, id, _):
            return id
        case let .toggle(section, toggle, _, _):
            return section.rawValue * 100 + 10 + toggle.rawValue
        case .clearHiddenUsers:
            return AyuGramSettingsSection.other.rawValue * 100 + 90
        }
    }

    static func <(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .toggle(_, toggle, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update(toggle, value)
            })
        case let .clearHiddenUsers(count):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Показать скрытых пользователей снова (\(count))", kind: count == 0 ? .disabled : .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearHiddenUsers()
            })
        }
    }
}

private func headerId(_ section: AyuGramSettingsSection) -> Int32 {
    return section.rawValue * 100
}

private func footerId(_ section: AyuGramSettingsSection) -> Int32 {
    return section.rawValue * 100 + 99
}

private func ayuGramSettingsEntries(settings: AyuSettings) -> [AyuGramSettingsEntry] {
    var entries: [AyuGramSettingsEntry] = []

    entries.append(.header(section: .ghost, id: headerId(.ghost), text: "РЕЖИМ ПРИЗРАКА"))
    entries.append(.toggle(section: .ghost, toggle: .ghostMode, title: "Режим призрака", value: settings.isGhostModeActive))
    entries.append(.footer(section: .ghost, id: footerId(.ghost), text: "Собеседники не увидят, что вы прочитали сообщения, просмотрели истории, были в сети или печатаете."))

    entries.append(.header(section: .ghostDetails, id: headerId(.ghostDetails), text: "НАСТРОЙКА"))
    entries.append(.toggle(section: .ghostDetails, toggle: .sendReadMessages, title: "Отправлять «прочитано»", value: settings.sendReadMessages))
    entries.append(.toggle(section: .ghostDetails, toggle: .sendReadStories, title: "Отправлять просмотр историй", value: settings.sendReadStories))
    entries.append(.toggle(section: .ghostDetails, toggle: .sendOnlinePackets, title: "Отправлять «в сети»", value: settings.sendOnlinePackets))
    entries.append(.toggle(section: .ghostDetails, toggle: .sendUploadProgress, title: "Отправлять «печатает»", value: settings.sendUploadProgress))
    entries.append(.toggle(section: .ghostDetails, toggle: .sendOfflinePacketAfterOnline, title: "Отправлять «не в сети»", value: settings.sendOfflinePacketAfterOnline))
    entries.append(.toggle(section: .ghostDetails, toggle: .markReadAfterAction, title: "Читать после действия", value: settings.markReadAfterAction))
    entries.append(.footer(section: .ghostDetails, id: footerId(.ghostDetails), text: "«Читать после действия»: когда вы отправляете сообщение, чат отмечается прочитанным даже в режиме призрака."))

    entries.append(.header(section: .history, id: headerId(.history), text: "ИСТОРИЯ СООБЩЕНИЙ"))
    entries.append(.toggle(section: .history, toggle: .saveDeletedMessages, title: "Сохранять удалённые сообщения", value: settings.saveDeletedMessages))
    entries.append(.toggle(section: .history, toggle: .saveMessagesHistory, title: "Сохранять историю изменений", value: settings.saveMessagesHistory))
    entries.append(.toggle(section: .history, toggle: .saveForBots, title: "Сохранять в чатах с ботами", value: settings.saveForBots))
    entries.append(.toggle(section: .history, toggle: .saveViewOnceMedia, title: "Сохранять одноразовые медиа", value: settings.saveViewOnceMedia))
    entries.append(.toggle(section: .history, toggle: .disableCopyRestrictions, title: "Обходить запрет копирования", value: settings.disableCopyRestrictions))
    entries.append(.footer(section: .history, id: footerId(.history), text: "Удалённые собеседником сообщения остаются в чате с пометкой 🧹. Прошлые версии отредактированных сообщений — в меню сообщения → «История изменений». «Сохранять одноразовые медиа» копирует фото и видео, отправленные с таймером, в кэш AyuGram до их удаления; открыть копию можно из меню сообщения. «Обходить запрет копирования» разрешает копировать и сохранять контент в каналах и группах, где это запрещено; пересылку по-прежнему запрещает сервер."))

    entries.append(.header(section: .other, id: headerId(.other), text: "ПРОЧЕЕ"))
    entries.append(.toggle(section: .other, toggle: .disableAds, title: "Без рекламы", value: settings.disableAds))
    entries.append(.toggle(section: .other, toggle: .showPeerId, title: "Показывать ID в профиле", value: settings.showPeerId))
    entries.append(.toggle(section: .other, toggle: .streamerMode, title: "Режим стримера", value: settings.streamerMode))
    entries.append(.clearHiddenUsers(count: settings.shadowBanIds.count))
    entries.append(.footer(section: .other, id: footerId(.other), text: "Режим стримера скрывает приложение на скриншотах и записи экрана. Скрыть сообщения человека в группах: зажмите его сообщение → «Скрывать сообщения автора»."))

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
        case .saveViewOnceMedia:
            settings.saveViewOnceMedia = value
        case .disableCopyRestrictions:
            settings.disableCopyRestrictions = value
        case .disableAds:
            settings.disableAds = value
        case .showPeerId:
            settings.showPeerId = value
        case .streamerMode:
            settings.streamerMode = value
        }
    }, clearHiddenUsers: {
        settings.clearShadowBans()
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
