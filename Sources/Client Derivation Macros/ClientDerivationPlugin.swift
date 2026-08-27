import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ClientDerivationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [ClientMacro.self]
}
