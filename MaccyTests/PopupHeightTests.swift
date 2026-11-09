import Defaults
import Testing
@testable import Maccy

extension SharedStateTests {
  @MainActor
  final class PopupHeightTests {
    let savedMaxVisibleItems = Defaults[.maxVisibleItems]
    let popup = AppState.shared.popup

    deinit {
      Defaults[.maxVisibleItems] = savedMaxVisibleItems
    }

    @Test("Maximum list height follows the visible items setting")
    func maximumListHeight() {
      Defaults[.maxVisibleItems] = 10
      let tenRows = popup.maximumListHeight

      Defaults[.maxVisibleItems] = 5
      let fiveRows = popup.maximumListHeight

      #expect(tenRows - fiveRows == 5 * Popup.itemHeight)
      #expect(fiveRows >= 5 * Popup.itemHeight)
    }

    @Test("A long history is capped at the visible items limit")
    func longHistoryIsCapped() {
      Defaults[.maxVisibleItems] = 5
      let chrome = popup.headerHeight + popup.extraTopHeight + popup.extraBottomHeight + popup.footerHeight

      popup.resize(height: 100 * Popup.itemHeight)

      #expect(popup.height == popup.maximumListHeight + chrome)
    }

    @Test("A short history keeps its own height")
    func shortHistoryIsNotPadded() {
      Defaults[.maxVisibleItems] = 10
      let chrome = popup.headerHeight + popup.extraTopHeight + popup.extraBottomHeight + popup.footerHeight

      popup.resize(height: 2 * Popup.itemHeight)

      #expect(popup.height == 2 * Popup.itemHeight + chrome)
    }
  }
}
