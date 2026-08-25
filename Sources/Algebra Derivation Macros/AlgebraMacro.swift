import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

public struct AlgebraMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct AlgebraDerivationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [AlgebraMacro.self]
}
