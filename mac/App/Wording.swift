// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The sentences of viewing a machine from other devices, from the shared remote-view crate's
/// `wording.json`, which the build copies from the pinned crate into `build/` and into the app. The
/// app keeps no copy of them: a key is looked up and its `{name}` placeholders are filled in one
/// pass, as the crate fills them. A key that is not in the file shows as itself, and a test fails
/// for every key the app asks for that the file lacks.
nonisolated enum Wording {
    /// A sentence by its key, with `values` for its placeholders.
    static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        guard let sentence = table[key] else { return key }
        return fill(sentence, values)
    }

    /// Every key and its English text.
    static var table: [String: String] { loaded }

    private static let loaded: [String: String] = {
        let url = Bundle.main.url(forResource: "wording", withExtension: "json") ?? built
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [:] }
        return file.keys.mapValues(\.en)
    }()

    /// Where the build leaves it, for what runs outside the app (the tests).
    private static var built: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../build/wording.json").standardized
    }

    private struct File: Decodable {
        struct Sentence: Decodable { let en: String }
        let keys: [String: Sentence]
    }

    /// `{name}` replaced by its value, once, so a value with braces in it is never filled in again.
    static func fill(_ text: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest.index(after: open)
            if let close = rest[after...].firstIndex(of: "}"),
               let value = values[String(rest[after..<close])] {
                out += value
                rest = rest[rest.index(after: close)...]
            } else {
                out += "{"
                rest = rest[after...]
            }
        }
        return out + rest
    }
}
