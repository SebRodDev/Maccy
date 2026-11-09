import AppKit
import Defaults
import Testing
@testable import Maccy

@MainActor
struct ContentKindTests {
  @Test("Single links", arguments: [
    "https://github.com/p0deje/Maccy",
    "http://example.com/path?query=1#anchor",
    "www.example.com",
    "  https://example.com  \n"
  ])
  func singleLinks(_ text: String) {
    #expect(ContentKindDetector.kind(ofText: text, application: nil) == .link)
  }

  @Test("Text that only contains or resembles a link", arguments: [
    "See https://example.com for details",
    "main.py",
    "example.com",
    "mailto:someone@example.com",
    "https://example.com\nhttps://example.org"
  ])
  func notLinks(_ text: String) {
    #expect(ContentKindDetector.kind(ofText: text, application: nil) != .link)
  }

  @Test("Code", arguments: [
    "func greet(name: String) -> String {\n  return \"Hello, \\(name)\"\n}",
    "def add(a, b):\n    return a + b",
    "const sum = (a, b) => {\n  return a + b;\n};",
    "if (x == 1) { y = 2; }"
  ])
  func code(_ text: String) {
    #expect(ContentKindDetector.kind(ofText: text, application: nil) == .code)
  }

  @Test("Prose", arguments: [
    "Hello world",
    "Thanks for the update, I will take a look tomorrow.",
    "Shopping list:\nMilk\nEggs\nBread",
    "Dear team,\nThe meeting moved to 3pm (room 4).\nSee you there."
  ])
  func prose(_ text: String) {
    #expect(ContentKindDetector.kind(ofText: text, application: nil) == .text)
  }

  @Test("Short commands copied from a terminal or editor are code")
  func codeApplication() {
    #expect(ContentKindDetector.kind(ofText: "ls -la | grep foo", application: "com.apple.Terminal") == .code)
    #expect(ContentKindDetector.kind(ofText: "ls -la | grep foo", application: "com.apple.Notes") == .text)
    #expect(ContentKindDetector.kind(ofText: "Just a comment", application: "com.microsoft.VSCode") == .text)
    #expect(ContentKindDetector.isCodeApplication("com.jetbrains.intellij"))
  }

  @Test("Images and files")
  func imagesAndFiles() throws {
    let image = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.png.rawValue, value: Data([0x89, 0x50]))
    ])
    #expect(ContentKindDetector.kind(of: image) == .image)

    let url = URL(fileURLWithPath: "/tmp/file.txt")
    let file = HistoryItem(contents: [
      HistoryItemContent(type: NSPasteboard.PasteboardType.fileURL.rawValue, value: url.dataRepresentation),
      HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: "file.txt".data(using: .utf8))
    ])
    #expect(ContentKindDetector.kind(of: file) == .file)
  }
}

extension SharedStateTests {
  @MainActor
  final class KindFilterTests {
    let savedSize = Defaults[.size]
    let savedSortBy = Defaults[.sortBy]
    let savedShowKindTabs = Defaults[.showKindTabs]
    let savedShowFooter = Defaults[.showFooter]
    let history = History.shared

    init() {
      History.shared.clearAll()
      History.shared.searchQuery = ""
      History.shared.activeKind = .all
      Defaults[.size] = 10
      Defaults[.sortBy] = .firstCopiedAt
      Defaults[.showKindTabs] = true
      Defaults[.showFooter] = true
    }

    deinit {
      Defaults[.size] = savedSize
      Defaults[.sortBy] = savedSortBy
      Defaults[.showKindTabs] = savedShowKindTabs
      Defaults[.showFooter] = savedShowFooter
    }

    @Test("Filtering by kind")
    func filteringByKind() {
      let prose = history.add(historyItem("hello world"))
      let link = history.add(historyItem("https://example.com"))
      let code = history.add(historyItem("let x = 1;\nlet y = x + 1;"))

      #expect(history.availableKinds == [.all, .text, .link, .code])

      history.activeKind = .link
      #expect(history.items.toArray() == [link])

      history.activeKind = .all
      #expect(history.items.toArray() == [code, link, prose])
    }

    @Test("Kind filter combines with search")
    func filteringWithSearch() async throws {
      history.add(historyItem("hello world"))
      let link = history.add(historyItem("https://hello.example.com"))
      history.add(historyItem("https://example.org"))

      history.activeKind = .link
      history.searchQuery = "hello"
      // Search results are throttled.
      try await Task.sleep(for: .milliseconds(500))
      #expect(history.items.toArray() == [link])

      history.searchQuery = ""
      try await Task.sleep(for: .milliseconds(500))
    }

    @Test("New copies appear only in their own tab")
    func addingWhileFiltered() {
      history.add(historyItem("hello world"))
      history.activeKind = .link

      let link = history.add(historyItem("https://example.com"))
      history.add(historyItem("another note"))

      #expect(history.items.toArray() == [link])
    }

    @Test("Deleting the last item of a tab switches back to All")
    func deletingLastItemOfKind() {
      let prose = history.add(historyItem("hello world"))
      let link = history.add(historyItem("https://example.com"))

      history.activeKind = .link
      history.delete(link)

      #expect(history.activeKind == .all)
      #expect(history.availableKinds == [.all, .text])
      #expect(history.items.toArray() == [prose])
    }

    @Test("Footer navigates tabs with items and the More button")
    func footerNavigation() {
      history.add(historyItem("hello world"))
      history.add(historyItem("https://example.com"))
      let footer = AppState.shared.footer

      let visible = footer.items.filter(\.isVisible)
      #expect(visible.map(\.kind) == [.all, .text, .link, nil])
      #expect(visible.last == footer.moreItem)

      Defaults[.showKindTabs] = false
      #expect(footer.items.map(\.title) == ["clear", "clear_all", "preferences", "about", "quit"])
    }

    @Test("Selecting a tab from the footer applies it")
    func selectingTab() throws {
      history.add(historyItem("hello world"))
      let link = history.add(historyItem("https://example.com"))
      let footer = AppState.shared.footer

      let linkTab = try #require(footer.tabItems.first { $0.kind == .link })
      AppState.shared.navigator.select(footerItem: linkTab)
      AppState.shared.select(flags: [])

      #expect(history.activeKind == .link)
      #expect(history.items.toArray() == [link])
      #expect(AppState.shared.navigator.leadHistoryItem == link)
    }

    private func historyItem(_ value: String) -> HistoryItem {
      let item = HistoryItem(contents: [
        HistoryItemContent(
          type: NSPasteboard.PasteboardType.string.rawValue,
          value: value.data(using: .utf8)
        )
      ])
      Storage.shared.context.insert(item)
      item.title = item.generateTitle()
      return item
    }
  }
}
