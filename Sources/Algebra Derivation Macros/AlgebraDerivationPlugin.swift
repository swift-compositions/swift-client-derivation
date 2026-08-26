import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct AlgebraDerivationPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [AlgebraMacro.self]
}
