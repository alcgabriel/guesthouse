import Foundation

/// The password the app gives a guest's account: random, and easy to read out and type. Four short
/// groups of lower-case letters and digits, leaving out the ones that look alike (0 o, 1 l i), so
/// "k7mn-p3xq-ab9d-w4ht". Sixteen characters from 29 is about 78 bits.
nonisolated enum GuestPassword {
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
    static let groups = 4
    static let groupLength = 4

    static func generate<Source: RandomNumberGenerator>(using source: inout Source) -> String {
        (0..<groups).map { _ in
            String((0..<groupLength).map { _ in alphabet.randomElement(using: &source)! })
        }
        .joined(separator: "-")
    }

    static func generate() -> String {
        var source = SystemRandomNumberGenerator()
        return generate(using: &source)
    }
}
