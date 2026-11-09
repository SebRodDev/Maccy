import SwiftUI

struct ConfirmationView<Content: View>: View {
  @Bindable var item: FooterItem
  @ViewBuilder let content: () -> Content

  var body: some View {
    if item.confirmation != nil, let suppressConfirmation = item.suppressConfirmation {
      content()
        .buttonAction {
          if suppressConfirmation.wrappedValue {
            item.action()
          } else {
            item.showConfirmation = true
          }
        }
        .footerItemConfirmation(item)
    } else {
      content()
        .buttonAction {
          item.action()
        }
    }
  }
}

// Presents the item's confirmation dialog whenever `item.showConfirmation` is set.
private struct FooterItemConfirmationModifier: ViewModifier {
  @Bindable var item: FooterItem

  func body(content: Content) -> some View {
    if let confirmation = item.confirmation, let suppressConfirmation = item.suppressConfirmation {
      content
        .confirmationDialog(confirmation.message, isPresented: $item.showConfirmation) {
          Text(confirmation.comment)
          Button(confirmation.confirm, role: .destructive) {
            item.action()
          }
          .accessibilityIdentifier("confirmation-confirm")
          Button(confirmation.cancel, role: .cancel) {}
        }
        .dialogSuppressionToggle(isSuppressed: suppressConfirmation)
    } else {
      content
    }
  }
}

extension View {
  func footerItemConfirmation(_ item: FooterItem) -> some View {
    modifier(FooterItemConfirmationModifier(item: item))
  }
}
