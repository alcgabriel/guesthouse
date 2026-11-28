import Foundation

/// What a check for a newer Guesthouse found, and the words for it. Plain data, so a test can hold
/// the sentences. The check only looks: nothing is downloaded or installed by it.
nonisolated enum UpdateState: Equatable {
    case newer(version: String, page: String)
    case latest
    case cantTell

    /// From the core's answer.
    init(json: String) {
        let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
        switch object?["state"] as? String {
        case "newer":
            self = .newer(version: object?["version"] as? String ?? "", page: object?["where"] as? String ?? "")
        case "latest": self = .latest
        default: self = .cantTell
        }
    }

    /// The line at the top of the page.
    func headline(current: String) -> String {
        switch self {
        case .newer(let version, _): String(localized: "Guesthouse \(version) is out")
        case .latest: String(localized: "Guesthouse \(current) is up to date")
        case .cantTell: String(localized: "Guesthouse \(current)")
        }
    }

    /// The line under it.
    func detail(lastChecked: Date?) -> String {
        switch self {
        case .newer:
            String(localized: "You have the older one. Open its page to get the new one; Guesthouse does not download or install it by itself yet.")
        case .latest:
            lastChecked.map { String(localized: "Last checked \($0.formatted(date: .abbreviated, time: .shortened))") }
                ?? String(localized: "Checked just now")
        case .cantTell:
            String(localized: "Could not tell whether there is a newer one. This needs the network, and a release that has published its file.")
        }
    }
}
