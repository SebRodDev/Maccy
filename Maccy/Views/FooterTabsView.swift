import AppKit
import Defaults
import Sauce
import SwiftUI

// Footer shown when type tabs are enabled: a row of content type tabs
// followed by a "More" button holding Clear, Preferences, About and Quit.
struct FooterTabsView: View {
  @Bindable var footer: Footer

  @Environment(AppState.self) private var appState
  @Default(.showFooter) private var showFooter

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .padding(.horizontal, Popup.horizontalSeparatorPadding)
        .padding(.bottom, Popup.verticalSeparatorPadding)

      HStack(spacing: 4) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 2) {
            ForEach(footer.tabItems.filter(\.isVisible)) { item in
              FooterTabView(item: item, isActive: appState.history.activeKind == item.kind)
            }
          }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

        FooterMoreButton(item: footer.moreItem)
      }
      .frame(height: Popup.itemHeight)
    }
    // The action items are only reachable through the menu and their shortcuts,
    // so their confirmation dialogs need a view that is always present.
    .background {
      ForEach(footer.actionItems) { item in
        Color.clear.footerItemConfirmation(item)
      }
    }
    .invisible(!showFooter)
    .frame(maxHeight: showFooter ? nil : 0)
    .padding(.bottom, showFooter ? Popup.verticalPadding : 0)
    .readHeight(appState, into: \.popup.footerHeight)
  }
}

private struct FooterTabView: View {
  @Bindable var item: FooterItem
  var isActive: Bool

  @Environment(AppState.self) private var appState

  private var background: Color {
    if item.isSelected {
      return Color.accentColor.opacity(0.8)
    }
    if isActive {
      return Color.primary.opacity(0.1)
    }
    // macOS 26 broke hovering if no background is present.
    return .white.opacity(0.001)
  }

  var body: some View {
    HStack(spacing: 5) {
      if let color = item.kind?.color {
        Circle()
          .fill(color)
          .frame(width: 7, height: 7)
          .overlay {
            if item.isSelected {
              Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1)
            }
          }
      }

      Text(LocalizedStringKey(item.title))
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.horizontal, 8)
    .frame(height: Popup.itemHeight - 2)
    .foregroundStyle(item.isSelected ? Color.white : (isActive ? Color.primary : Color.secondary))
    .background(background, in: .rect(cornerRadius: Popup.cornerRadius))
    .contentShape(.rect)
    .buttonAction(item.action)
    .hoverSelectionId(item.id)
    .onHover { hovering in
      if hovering && appState.preview.state.isOpen {
        appState.preview.togglePreview()
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(LocalizedStringKey(item.title)))
    .accessibilityAddTraits(isActive ? .isSelected : [])
    .accessibilityIdentifier("footer-tab-\(item.kind?.rawValue ?? "")")
  }
}

private struct FooterMoreButton: View {
  @Bindable var item: FooterItem

  @Environment(AppState.self) private var appState

  var body: some View {
    Image(systemName: "ellipsis.circle")
      .frame(width: 26, height: Popup.itemHeight - 2)
      .foregroundStyle(item.isSelected ? Color.white : Color.secondary)
      .background(
        item.isSelected ? Color.accentColor.opacity(0.8) : .white.opacity(0.001),
        in: .rect(cornerRadius: Popup.cornerRadius)
      )
      .contentShape(.rect)
      .buttonAction(item.action)
      .hoverSelectionId(item.id)
      .onHover { hovering in
        if hovering && appState.preview.state.isOpen {
          appState.preview.togglePreview()
        }
      }
      .onGeometryChange(for: CGRect.self) { proxy in
        proxy.frame(in: .global)
      } action: { frame in
        FooterMenu.anchor = frame
      }
      .help(Text(item.help ?? ""))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(LocalizedStringKey(item.title)))
      .accessibilityIdentifier("footer-more")
  }
}

// The menu opened by the "More" button, built from the footer's action items.
@MainActor
enum FooterMenu {
  // Frame of the "More" button in the popup's coordinates (top-left origin).
  static var anchor: CGRect = .zero

  private static let sections = [["clear", "clear_all"], ["preferences", "about"], ["quit"]]

  static func show() {
    guard let view = AppState.shared.appDelegate?.panel.contentView else { return }

    let footer = AppState.shared.footer
    let target = FooterMenuTarget()
    let menu = NSMenu()
    menu.autoenablesItems = false

    for (index, section) in sections.enumerated() {
      if index > 0 {
        menu.addItem(.separator())
      }

      for title in section {
        guard let item = footer.actionItems.first(where: { $0.title == title }) else { continue }
        menu.addItem(menuItem(for: item, target: target))
      }
    }

    let location = NSPoint(
      x: anchor.minX,
      y: view.isFlipped ? anchor.maxY : view.bounds.height - anchor.maxY
    )
    // Blocks until the menu is dismissed, which keeps `target` alive meanwhile.
    _ = menu.popUp(positioning: nil, at: location, in: view)
  }

  private static func menuItem(for item: FooterItem, target: FooterMenuTarget) -> NSMenuItem {
    let menuItem = NSMenuItem(
      title: NSLocalizedString(item.title, comment: ""),
      action: #selector(FooterMenuTarget.performItem(_:)),
      keyEquivalent: ""
    )
    menuItem.target = target
    menuItem.representedObject = item

    if let shortcut = item.shortcuts.first, let key = shortcut.key {
      if key == .delete {
        menuItem.keyEquivalent = "\u{8}"
      } else if let character = Sauce.shared.character(
        for: Int(Sauce.shared.keyCode(for: key)),
        modifiers: .cocoa([])
      ) {
        menuItem.keyEquivalent = character.lowercased()
      }
      menuItem.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    return menuItem
  }
}

private class FooterMenuTarget: NSObject {
  @MainActor @objc
  func performItem(_ sender: NSMenuItem) {
    guard let item = sender.representedObject as? FooterItem else { return }

    if item.confirmation != nil, item.suppressConfirmation?.wrappedValue == false {
      item.showConfirmation = true
    } else {
      item.action()
    }
  }
}
