import SwiftSyntax

extension Macro {
    struct Diagnostic: Swift.Error {
        let message: String
        let node: Syntax
    }
}
