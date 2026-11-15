import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI
import PresentationDataUtils
import AccountContext
import TextFormat
import AyuSettings

/// Shows the system share sheet for saved files (save to Photos or Files, send elsewhere).
public func ayuPresentSavedFiles(context: AccountContext, urls: [URL]) {
    guard !urls.isEmpty else {
        return
    }
    let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
    context.sharedContext.mainWindow?.presentNative(controller)
}

private final class AyuEditHistoryArguments {
    let openFiles: ([String]) -> Void

    init(openFiles: @escaping ([String]) -> Void) {
        self.openFiles = openFiles
    }
}

private enum AyuEditHistoryEntryItem: ItemListNodeEntry {
    case current(text: String, date: String)
    case header(String)
    case version(index: Int32, text: String, date: String)
    case attachments(index: Int32, files: [String])

    var section: ItemListSectionId {
        switch self {
        case .current:
            return 0
        case .header, .version, .attachments:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .current:
            return 0
        case .header:
            return 1
        case let .version(index, _, _):
            return 2 + index * 2
        case let .attachments(index, _):
            return 3 + index * 2
        }
    }

    static func <(lhs: AyuEditHistoryEntryItem, rhs: AyuEditHistoryEntryItem) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuEditHistoryArguments
        switch self {
        case let .current(text, date):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: "Сейчас · \(date)", text: text.isEmpty ? "(без текста)" : text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .version(_, text, date):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: date, text: text.isEmpty ? "(без текста)" : text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .attachments(_, files):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "📎 Прежнее вложение (\(files.count))", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.openFiles(files)
            })
        }
    }
}

/// AyuGram "Edit history": the current text and every saved previous version, newest first.
public func ayuEditHistoryController(context: AccountContext, message: EngineMessage) -> ViewController {
    let arguments = AyuEditHistoryArguments(openFiles: { files in
        let urls = files.compactMap { ayuSavedMediaUrl(accountPeerId: context.account.peerId, name: $0) }
        ayuPresentSavedFiles(context: context, urls: urls)
    })

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings
        let dateTimeFormat = presentationData.dateTimeFormat
        let history = ayuEditHistory(accountPeerId: context.account.peerId, messageId: message.id)

        var entries: [AyuEditHistoryEntryItem] = []
        let currentDate = message.editedTime ?? message.timestamp
        entries.append(.current(text: message.text, date: stringForMediumDate(timestamp: currentDate, strings: strings, dateTimeFormat: dateTimeFormat)))
        if !history.isEmpty {
            entries.append(.header("ПРЕДЫДУЩИЕ ВЕРСИИ"))
            var index: Int32 = 0
            for entry in history.reversed() {
                entries.append(.version(index: index, text: entry.text, date: stringForMediumDate(timestamp: entry.date, strings: strings, dateTimeFormat: dateTimeFormat)))
                if let files = entry.mediaFiles, !files.isEmpty {
                    entries.append(.attachments(index: index, files: files))
                }
                index += 1
            }
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("История изменений"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
