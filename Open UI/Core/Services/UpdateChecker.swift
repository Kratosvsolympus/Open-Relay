import Foundation
import SwiftUI

// MARK: - Update Info Model

struct AppUpdateInfo: Identifiable, Sendable {
    /// Stable identity is the version string — each release is unique.
    var id: String { version }

    let version: String          // e.g. "3.4.2"
    let tagName: String          // e.g. "v3.4.2"
    let releaseNotes: String     // Markdown-formatted release notes
    let releaseURL: URL          // GitHub tag/release page URL
}

// MARK: - Atom Parser Result

private struct AtomEntry {
    let tagName: String
    let releaseNotes: String
}

// MARK: - Update Checker

/// Checks the GitHub Atom feed for newer versions of Open Relay and
/// surfaces an update notice to the user when one is found.
///
/// Uses the Atom feed (`/releases.atom`) which works for both lightweight
/// tags and formal GitHub Releases — the standard `/releases` REST endpoint
/// returns `[]` for repos that publish tag-based releases without formal releases.
///
/// - Checks on every app launch and on-demand from Settings → About.
/// - Shows the sheet on every launch when a newer version exists.
/// - After the user taps "Later", the sheet hides but `pendingUpdate` stays
///   set so an update icon can reopen the sheet.
/// - Fails silently on any network or parsing error.
@Observable
@MainActor
final class UpdateChecker {

    // MARK: - Published State

    /// Non-nil when there is a newer version available that the user hasn't dismissed.
    /// Setting this to `nil` closes the sheet; the update icon uses `pendingUpdate`.
    var availableUpdate: AppUpdateInfo? = nil

    /// Persists across sheet dismissal so the update icon stays visible.
    /// Only cleared when the next version check finds no newer release.
    var pendingUpdate: AppUpdateInfo? = nil

    /// `true` while an on-demand check is in progress (used by the Settings row).
    var isChecking: Bool = false

    // MARK: - Private Constants

    private static let atomFeedURL = URL(string: "https://github.com/Ichigo3766/Open-Relay/releases.atom")!

    // MARK: - Public API

    /// Checks for updates unconditionally. Safe to call on every app launch.
    /// Shows the sheet every launch when a newer version exists.
    /// Clears `pendingUpdate` (and thus the icon) when the app is up-to-date.
    func checkForUpdates() async {
        do {
            guard let entry = try await fetchLatestAtomEntry() else { return }

            // Tag name is typically "v3.4.2" — strip leading v/V for comparison
            let tagName = entry.tagName
            let remoteVersion = tagName.trimmingCharacters(in: .init(charactersIn: "vV"))
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            guard isNewer(remote: remoteVersion, than: localVersion) else {
                // Up to date — clear any lingering update state
                availableUpdate = nil
                pendingUpdate = nil
                return
            }

            let releaseURL = URL(string: "https://github.com/Ichigo3766/Open-Relay/releases/tag/\(tagName)")
                ?? Self.atomFeedURL

            let info = AppUpdateInfo(
                version: remoteVersion,
                tagName: tagName,
                releaseNotes: entry.releaseNotes,
                releaseURL: releaseURL
            )
            pendingUpdate = info
            availableUpdate = info   // Triggers the sheet
        } catch {
            // Fail silently — update check is non-critical
        }
    }

    /// On-demand check triggered from Settings → About.
    /// Shows a spinner while checking; if up-to-date, the caller can show
    /// a "You're up to date" message by observing `isChecking` going false
    /// with `availableUpdate == nil`.
    func checkForUpdatesManually() async {
        isChecking = true
        defer { isChecking = false }
        do {
            guard let entry = try await fetchLatestAtomEntry() else { return }
            let tagName = entry.tagName
            let remoteVersion = tagName.trimmingCharacters(in: .init(charactersIn: "vV"))
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            guard isNewer(remote: remoteVersion, than: localVersion) else {
                availableUpdate = nil
                pendingUpdate = nil
                return
            }
            let releaseURL = URL(string: "https://github.com/Ichigo3766/Open-Relay/releases/tag/\(tagName)")
                ?? Self.atomFeedURL
            let info = AppUpdateInfo(
                version: remoteVersion,
                tagName: tagName,
                releaseNotes: entry.releaseNotes,
                releaseURL: releaseURL
            )
            pendingUpdate = info
            availableUpdate = info
        } catch { }
    }

    /// Called when the user taps "Later" — hides the sheet but keeps
    /// `pendingUpdate` so the update icon remains visible.
    func dismissUpdate() {
        availableUpdate = nil
    }

    /// Called by the update icon — re-presents the sheet for the pending update.
    func reopenUpdate() {
        availableUpdate = pendingUpdate
    }

    // MARK: - Private Helpers

    private func fetchLatestAtomEntry() async throws -> AtomEntry? {
        var request = URLRequest(url: Self.atomFeedURL, timeoutInterval: 10)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

        let parser = AtomFeedParser(data: data)
        return parser.parseFirstEntry()
    }

    /// Returns `true` if `remote` is strictly newer than `local`
    /// using standard semantic versioning (major.minor.patch).
    private func isNewer(remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        let maxLen = max(r.count, l.count)
        for i in 0..<maxLen {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

// MARK: - Atom Feed XML Parser

/// Lightweight SAX parser for GitHub's Atom release feed.
/// Extracts the first `<entry>` — its title (which contains the tag) and
/// the `<content>` HTML body converted to markdown.
private final class AtomFeedParser: NSObject, XMLParserDelegate {

    private let data: Data

    // Parser state
    private var result: AtomEntry?
    private var currentElement = ""
    private var currentContent = ""
    private var currentTagName = ""
    private var insideEntry = false

    init(data: Data) {
        self.data = data
    }

    func parseFirstEntry() -> AtomEntry? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return result
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentContent = ""
        if elementName == "entry" {
            insideEntry = true
            currentTagName = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentContent += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) {
            currentContent += s
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard insideEntry else {
            currentContent = ""
            return
        }

        switch elementName {
        case "title":
            // Title format: "v3.4.2.1: release: v3.4.2" or "release: v3.4.2" or just "v3.4.2"
            // Use a greedy match that captures all numeric segments (e.g. v3.4.2.1)
            let title = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = title.range(of: #"v\d+(?:\.\d+)+"#, options: .regularExpression) {
                currentTagName = String(title[match])
            }

        case "content":
            let body = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty && !currentTagName.isEmpty {
                result = AtomEntry(tagName: currentTagName,
                                   releaseNotes: htmlToMarkdown(body))
                parser.abortParsing()  // Only need the first entry
            }

        case "entry":
            insideEntry = false

        default:
            break
        }

        currentContent = ""
    }

    // MARK: - HTML → Markdown

    /// Converts GitHub's Atom entry HTML body to clean markdown text.
    /// Handles h3 headings, ul/li lists, bold, inline code, paragraphs.
    private func htmlToMarkdown(_ html: String) -> String {
        var s = html

        // Unescape HTML entities
        s = s
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Headings
        s = rx(s, #"<h1[^>]*>(.*?)</h1>"#,    "# $1\n")
        s = rx(s, #"<h2[^>]*>(.*?)</h2>"#,    "## $1\n")
        s = rx(s, #"<h3[^>]*>(.*?)</h3>"#,    "### $1\n")
        s = rx(s, #"<h4[^>]*>(.*?)</h4>"#,    "#### $1\n")

        // Bold / italic
        s = rx(s, #"<strong[^>]*>(.*?)</strong>"#, "**$1**")
        s = rx(s, #"<b[^>]*>(.*?)</b>"#,           "**$1**")
        s = rx(s, #"<em[^>]*>(.*?)</em>"#,         "_$1_")
        s = rx(s, #"<i[^>]*>(.*?)</i>"#,           "_$1_")

        // Inline code
        s = rx(s, #"<code[^>]*>(.*?)</code>"#, "`$1`")

        // List items → markdown bullets
        s = rx(s, #"<li[^>]*>(.*?)</li>"#, "- $1\n")

        // Block containers → newlines
        s = rx(s, #"</?(?:ul|ol|p|div|br)[^>]*>"#, "\n")

        // Strip any remaining HTML tags
        s = rx(s, #"<[^>]+>"#, "")

        // Collapse excessive blank lines
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rx(_ input: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
