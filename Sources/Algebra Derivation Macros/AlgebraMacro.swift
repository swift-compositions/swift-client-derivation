import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Witness_Derivation_Core

public struct AlgebraMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDeclaration = declaration.as(ProtocolDeclSyntax.self) else {
            throw DiagnosticsError(
                diagnostics: [
                    .init(
                        node: node,
                        message: AlgebraMessage(
                            "Algebra attaches to a protocol declaration only."
                        )
                    )
                ]
            )
        }
        guard protocolDeclaration.name.text == "Signature" else {
            throw DiagnosticsError(
                diagnostics: [
                    .init(
                        node: protocolDeclaration.name,
                        message: AlgebraMessage(
                            "Algebra derives a protocol named Signature."
                        )
                    )
                ]
            )
        }

        // SwiftSyntax 602 has no module-selector child, so preserve the
        // compiler's exact `Client::Client` token sequence.
        let client = TypeSyntax(
            IdentifierTypeSyntax(
                UnexpectedNodesSyntax([
                    Syntax(TokenSyntax.identifier("Client")),
                    Syntax(TokenSyntax.colonToken()),
                    Syntax(TokenSyntax.colonToken()),
                ]),
                name: .identifier("Client")
            )
        )
        let call = protocolDeclaration.attributes.contains(where: { element in
            guard case .attribute(let attribute) = element,
                  let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name
            else {
                return false
            }
            return name.text == "Calls"
        })
            ? TypeSyntax(IdentifierTypeSyntax(name: .identifier("Call")))
            : nil
        do throws(WitnessDerivation.Diagnostic) {
            return try WitnessDerivation.expansion(
                of: protocolDeclaration,
                configuration: .init(
                    name: .identifier("Client"),
                    access: .public,
                    storage: .client(client),
                    call: call
                )
            )
        } catch {
            throw DiagnosticsError(
                diagnostics: [
                    .init(
                        node: error.node,
                        message: AlgebraMessage(error.message)
                    )
                ]
            )
        }
    }
}
