import Foundation
import GuesthouseCore

/// What the core made of a report request, for the sheet to show.
nonisolated struct PreparedReport {
    nonisolated struct File: Identifiable { let name: String; let bytes: Int; var id: String { name } }
    nonisolated struct Missing: Identifiable { let name: String; let reason: String; var id: String { name } }
    let archive: String
    let folder: String
    let files: [File]
    let missing: [Missing]
    let notes: [String]
    let summary: [String: String]
    let summaryHeader: String
    let bytes: Int
    let warning: String?
}

extension Core {
    /// Makes a report, writing it in the Reports folder and sending nothing. Returns it, or why not.
    nonisolated static func prepareReport(json: String) -> Result<PreparedReport, ReportFailure> {
        guard let text = guesthouse_report_prepare(json)
        else { return .failure(ReportFailure(text: "The core gave no answer.")) }
        defer { guesthouse_string_free(text) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
        else { return .failure(ReportFailure(text: "The core's answer was not readable.")) }
        if let error = object["error"] as? String { return .failure(ReportFailure(text: error)) }
        let files = (object["files"] as? [[String: Any]] ?? []).compactMap { entry -> PreparedReport.File? in
            guard let name = entry["name"] as? String, let bytes = entry["bytes"] as? Int else { return nil }
            return .init(name: name, bytes: bytes)
        }
        let missing = (object["missing"] as? [[String: Any]] ?? []).compactMap { entry -> PreparedReport.Missing? in
            guard let name = entry["name"] as? String, let reason = entry["reason"] as? String else { return nil }
            return .init(name: name, reason: reason)
        }
        return .success(PreparedReport(
            archive: object["archive"] as? String ?? "", folder: object["folder"] as? String ?? "",
            files: files, missing: missing, notes: object["notes"] as? [String] ?? [],
            summary: object["summary"] as? [String: String] ?? [:],
            summaryHeader: object["summary_header"] as? String ?? "", bytes: object["bytes"] as? Int ?? 0,
            warning: object["warning"] as? String))
    }

    /// Sends a prepared report. **Only the sheet's Send button calls this.** Returns the report's ID
    /// and the link that opens an issue about it, or why it did not go.
    nonisolated static func sendReport(_ report: PreparedReport) -> Result<(id: String, issueLink: String), ReportFailure> {
        guard let summary = try? JSONSerialization.data(withJSONObject: report.summary),
              let summaryText = String(data: summary, encoding: .utf8),
              let text = guesthouse_report_send(report.archive, report.summaryHeader, summaryText)
        else { return .failure(ReportFailure(text: "The core gave no answer.")) }
        defer { guesthouse_string_free(text) }
        let object = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any]
        if let id = object?["id"] as? String {
            return .success((id, object?["issue_link"] as? String ?? ""))
        }
        return .failure(ReportFailure(text: object?["error"] as? String ?? "The report was not sent."))
    }
}

nonisolated struct ReportFailure: Error { let text: String }

extension Core {
    /// Judges a start check in the core (`start_checks.rs`) from facts the app read. Returns the
    /// core's answer as JSON text, or an empty answer if it gave none.
    static func startCheck(_ request: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let json = String(data: data, encoding: .utf8),
              let text = guesthouse_start_check(json)
        else { return "{}" }
        defer { guesthouse_string_free(text) }
        return String(cString: text)
    }

    /// What to say about creating a machine next to ones that run, or nil.
    static func memoryAdvice(newMB: Int, runningMB: Int, hostMB: Int) -> String? {
        let answer = startCheck(["check": "advice", "new_mb": newMB, "running_mb": runningMB, "host_mb": hostMB])
        let object = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any]
        return object?["warning"] as? String
    }
}
