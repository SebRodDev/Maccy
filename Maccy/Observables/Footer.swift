import Defaults
import SwiftUI

@Observable
class Footer: ItemsContainer {
  // Clear, Clear all, Preferences, About and Quit. Their keyboard shortcuts
  // look them up here regardless of how the footer is displayed.
  var actionItems: [FooterItem] = []

  // With type tabs enabled the footer becomes a row of tabs followed by
  // a "More" button that opens the action items in a menu.
  var tabItems: [FooterItem] = []
  let moreItem: FooterItem

  // Items reachable with keyboard navigation, in display order.
  var items: [FooterItem] {
    showKindTabs ? tabItems + [moreItem] : actionItems
  }

  var showKindTabs: Bool {
    return Defaults[.showKindTabs]
  }

  var selectedItem: FooterItem? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var suppressClearAlert = Binding<Bool>(
    get: { Defaults[.suppressClearAlert] },
    set: { Defaults[.suppressClearAlert] = $0 }
  )

  private var showFooter: Bool {
    return Defaults[.showFooter]
  }
  var containerVisible: Bool {
    return showFooter
  }

  init() { // swiftlint:disable:this function_body_length
    tabItems = ContentKind.allCases.map { kind in
      let item = FooterItem(title: kind.titleKey) {
        AppState.shared.history.activeKind = kind
      }
      item.kind = kind
      item.isAvailable = { AppState.shared.history.availableKinds.contains(kind) }
      return item
    }

    moreItem = FooterItem(title: "more", help: "more_tooltip") {
      FooterMenu.show()
    }

    actionItems = [
      FooterItem(
        title: "clear",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option])],
        help: "clear_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clear()
        }
      },
      FooterItem(
        title: "clear_all",
        shortcuts: [KeyShortcut(key: .delete, modifierFlags: [.command, .option, .shift])],
        help: "clear_all_tooltip",
        confirmation: .init(
          message: "clear_alert_message",
          comment: "clear_alert_comment",
          confirm: "clear_alert_confirm",
          cancel: "clear_alert_cancel"
        ),
        suppressConfirmation: suppressClearAlert
      ) {
        Task { @MainActor in
          AppState.shared.history.clearAll()
        }
      },
      FooterItem(
        title: "preferences",
        shortcuts: [KeyShortcut(key: .comma)]
      ) {
        Task { @MainActor in
          AppState.shared.openPreferences()
        }
      },
      FooterItem(
        title: "about",
        help: "about_tooltip"
      ) {
        AppState.shared.openAbout()
      },
      FooterItem(
        title: "quit",
        shortcuts: [KeyShortcut(key: .q)],
        help: "quit_tooltip"
      ) {
        AppState.shared.quit()
      }
    ]
  }
}
