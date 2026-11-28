import Foundation

/// The words of bug reporting, the Linux and Windows apps' own: the kinds of problem (each with
/// the word the report is sorted by and what the person reads) and the sentence that says what a
/// report is, where it goes and what is taken out of it. Plain data, so a test can hold them to
/// the other hosts' words.
nonisolated enum ReportKind: String, CaseIterable, Identifiable {
    case wontStart = "wont-start"
    case crashed
    case picture
    case slow
    case installFailed = "install-failed"
    case other

    var id: String { rawValue }

    /// What the person reads.
    var label: String {
        switch self {
        case .wontStart: String(localized: "Won't start")
        case .crashed: String(localized: "Crashed")
        case .picture: String(localized: "Picture is wrong")
        case .slow: String(localized: "Slow")
        case .installFailed: String(localized: "Install failed")
        case .other: String(localized: "Something else")
        }
    }
}

nonisolated enum ReportWords {
    /// How long the server keeps a report.
    static let keptDays = 30

    /// What a report is and where it goes, said before anything is sent.
    static var whatIsSent: String {
        String(localized: "A report holds the app's log, the chosen machine's logs from its last runs and its settings, and facts about this Mac: its model, chip, system and memory. It goes to Guesthouse's developer, is read by the developer and their automation tools, and is deleted after \(keptDays) days. Your user name, host name and home folder are taken out where they're found, and so are passwords, pairing keys, device fingerprints, pairing codes and serial numbers, but logs are free text, so something personal can still be in them. Nothing is sent until you press Send.")
    }

    static let noMachine = String(localized: "None, it's about the app")

    static let serialNote = String(localized: "What the guest wrote to its serial port. Turned off, the app's log can still hold a few of the guest's answers to the app's own scripts.")

    static let sentBody = String(localized: "Mention its ID wherever you talk about this problem.\n\nAlso open a GitHub issue? Your browser opens on one filled in with the ID and the report's facts, for you to check before you post it.")

    /// Under "The Report Wasn't Sent": what to do instead.
    static func notSentBody(reason: String) -> String {
        String(localized: "\(reason)\n\nSave the report to a file so it isn't lost. You can attach it to an issue.")
    }
}
