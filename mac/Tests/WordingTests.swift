// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing

struct WordingTests {
    @Test func everyKeyTheAppAsksForIsInTheSharedFile() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../App").standardized
        let files = try FileManager.default.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(pattern: #""(remote_view\.[a-z_.0-9]+)""#)
        var asked = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                asked.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        #expect(asked.count > 20)
        #expect(!Wording.table.isEmpty)
        for key in asked.sorted() {
            #expect(Wording.table[key] != nil, "\(key) is not in wording.json")
        }
    }

    @Test func aValueIsPutInOnceAndNeverFilledInAgain() {
        #expect(Wording.fill("{name} wants to pair", ["name": "{name}"]) == "{name} wants to pair")
        #expect(Wording.fill("Remove {name}?", ["name": "Pat's iPad"]) == "Remove Pat's iPad?")
        #expect(Wording.fill("{ other }", [:]) == "{ other }")
    }

    @Test func aKeyThatIsNotThereShowsAsItself() {
        #expect(Wording.text("remote_view.no_such_sentence") == "remote_view.no_such_sentence")
    }
}
