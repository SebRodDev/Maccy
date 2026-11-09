import AppKit
import SwiftUI

// The kind of content a history item holds, used to group items into tabs.
enum ContentKind: String, CaseIterable, Identifiable {
  case all
  case text
  case link
  case code
  case image
  case file

  var id: Self { self }

  // Key in Localizable.strings.
  var titleKey: String { "content_kind_\(rawValue)" }

  var color: Color? {
    switch self {
    case .all: nil
    case .text: .gray
    case .link: .blue
    case .code: .purple
    case .image: .orange
    case .file: .green
    }
  }
}

enum ContentKindDetector {
  // Apps where copied text is very likely to be code or a shell command.
  static let codeApplications: Set<String> = [
    "com.apple.dt.Xcode",
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders",
    "com.todesktop.230313mzl4w4u92", // Cursor
    "com.mitchellh.ghostty",
    "dev.warp.Warp-Stable",
    "dev.zed.Zed",
    "com.sublimetext.4",
    "com.panic.Nova",
    "com.barebones.bbedit",
    "net.kovidgoyal.kitty",
    "io.alacritty"
  ]
  static let codeApplicationPrefixes = ["com.jetbrains."]

  // Large clipboard entries are inspected only partially to keep detection cheap.
  private static let maxInspectedLength = 4_000
  private static let maxInspectedLines = 60

  private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
  // swiftlint:disable:next force_try
  private static let keywordRegex = try! NSRegularExpression(
    pattern: "^\\s*(func|def|class|struct|enum|interface|import|from|let|var|const|function|return|"
      + "if|elif|else|for|while|switch|case|public|private|protected|static|async|await|try|catch|"
      + "package|fn|impl|use|#include|#import|#define|SELECT|INSERT|UPDATE|DELETE|CREATE)\\b",
    options: [.anchorsMatchLines]
  )
  // Command line flags, pipes and command substitution.
  // swiftlint:disable:next force_try
  private static let shellRegex = try! NSRegularExpression(
    pattern: "(^|\\s)--?[A-Za-z][\\w-]*|\\s\\|\\s|\\$\\(|^\\s*\\$\\s",
    options: [.anchorsMatchLines]
  )
  private static let operatorTokens = ["=>", "->", "==", "!=", "&&", "||", "::", ":=", "+=", "</", "/>"]
  private static let codeLineEndings: Set<Character> = ["{", "}", ";", "(", ")", "[", "]", ","]

  static func kind(of item: HistoryItem) -> ContentKind {
    if item.imageData != nil {
      return .image
    }

    if !item.fileURLs.isEmpty {
      return .file
    }

    guard let text = item.text ?? item.rtf?.string else {
      return .text
    }

    return kind(ofText: text, application: item.application)
  }

  static func kind(ofText text: String, application: String?) -> ContentKind {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .text
    }

    if isSingleLink(trimmed) {
      return .link
    }

    if looksLikeCode(trimmed, application: application) {
      return .code
    }

    return .text
  }

  // Only text that is exactly one link with an explicit scheme or "www." counts,
  // so that prose containing a link or file names like "main.py" stay text.
  static func isSingleLink(_ text: String) -> Bool {
    guard !text.contains(where: \.isWhitespace) else {
      return false
    }

    let lowercased = text.lowercased()
    guard lowercased.contains("://") || lowercased.hasPrefix("www.") else {
      return false
    }

    let range = NSRange(text.startIndex..., in: text)
    guard let match = linkDetector?.firstMatch(in: text, range: range) else {
      return false
    }

    return match.range == range && match.url?.scheme != "mailto"
  }

  static func looksLikeCode(_ text: String, application: String?) -> Bool {
    let sample = String(text.prefix(maxInspectedLength))
    let lines = sample
      .split(whereSeparator: \.isNewline)
      .prefix(maxInspectedLines)
      .map { String($0) }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard !lines.isEmpty else {
      return false
    }

    let score = codeScore(sample, lines: lines)

    if isCodeApplication(application) {
      return score >= 1
    }

    if lines.count >= 2 {
      return score >= 2
    }

    return score >= 3
  }

  static func isCodeApplication(_ application: String?) -> Bool {
    guard let application else {
      return false
    }

    return codeApplications.contains(application)
      || codeApplicationPrefixes.contains { application.hasPrefix($0) }
  }

  // Each signal counts once, so long text cannot score high by repeating one trait.
  private static func codeScore(_ sample: String, lines: [String]) -> Int {
    var score = 0

    let range = NSRange(sample.startIndex..., in: sample)
    if keywordRegex.firstMatch(in: sample, range: range) != nil {
      score += 1
    }

    if operatorTokens.contains(where: { sample.contains($0) }) {
      score += 1
    }

    if shellRegex.firstMatch(in: sample, range: range) != nil {
      score += 1
    }

    let codeEndingLines = lines.filter { line in
      guard let last = line.trimmingCharacters(in: .whitespaces).last else { return false }
      return codeLineEndings.contains(last)
    }
    if codeEndingLines.count * 2 >= lines.count {
      score += 1
    }

    let indentedLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
    if lines.count >= 2, !indentedLines.isEmpty {
      score += 1
    }

    if sample.contains(where: { "{}".contains($0) }) {
      score += 1
    }

    return score
  }
}
