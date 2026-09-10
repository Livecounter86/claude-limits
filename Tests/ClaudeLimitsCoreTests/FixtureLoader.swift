import Foundation

struct FixtureMissing: Error, CustomStringConvertible {
    let name: String
    var description: String { "fixture \(name).json not found in test bundle" }
}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw FixtureMissing(name: name)
        }
        return try Data(contentsOf: url)
    }
}
