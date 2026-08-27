import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [SwiftSyntaxMacros.Macro.Type] = [Macro.self]
}
