import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct Macro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let signature = declaration.as(ProtocolDeclSyntax.self) else {
            throw diagnostics(
                node: node,
                message: "Client attaches to a protocol declaration only."
            )
        }
        guard signature.name.text == "Signature" else {
            throw diagnostics(
                node: signature.name,
                message: "Client derives a protocol named Signature."
            )
        }
        guard !signature.memberBlock.members.isEmpty else {
            throw diagnostics(
                node: signature,
                message: "Client requires at least one operation or composed scope."
            )
        }

        let members = signature.memberBlock.members
        do {
            if members.allSatisfy({ $0.decl.is(FunctionDeclSyntax.self) }) {
                let operations = try members.map(Operation.init)
                return [operationClient(operations)]
            }
            if members.allSatisfy({ $0.decl.is(VariableDeclSyntax.self) }) {
                let scopes = try members.map(Scope.init)
                return [composedClient(scopes)]
            }
            throw Diagnostic(
                message: "Client cannot mix operations and composed scopes in one signature.",
                node: Syntax(signature)
            )
        } catch let error as Diagnostic {
            throw diagnostics(node: error.node, message: error.message)
        }
    }

    private static func operationClient(
        _ operations: [Operation]
    ) -> DeclSyntax {
        let properties = operations.map(\.property).joined(separator: " ")
        let parameters = operations.map(\.parameter)
            .joined(separator: ", ")
        let assignments = operations.map(\.assignment)
            .joined(separator: "; ")
        let closures = operations.map(\.closure)
            .joined(separator: ", ")
        let implementations = operations.map(\.implementation)
            .joined(separator: "; ")
        let remote = operationRemote(operations)
        return """
            public struct Client {
                \(raw: properties)
                public init(\(raw: parameters)) {
                    \(raw: assignments)
                }
                public init(\(raw: closures)) {
                    \(raw: implementations)
                }
                \(raw: remote)
            }
            """
    }

    private static func operationRemote(
        _ operations: [Operation]
    ) -> String {
        let properties = operations.map(\.remote)
            .joined(separator: " ")
        let parameters = operations.map(\.external)
            .joined(separator: ", ")
        let assignments = operations.map(\.assignment)
            .joined(separator: "; ")
        return """
            public struct Remote<External: Swift.Error> {
                \(properties)
                public init(\(parameters)) {
                    \(assignments)
                }
            }
            """
    }

    private static func composedClient(
        _ scopes: [Scope]
    ) -> DeclSyntax {
        let properties = scopes.map { scope in
            "public let \(scope.name): \(scope.type)"
        }.joined(separator: " ")
        let parameters = scopes.map { scope in
            "\(scope.name): \(scope.type)"
        }.joined(separator: ", ")
        let assignments = scopes.map { scope in
            "self.\(scope.name) = \(scope.name)"
        }.joined(separator: "; ")
        let remote = composedRemote(scopes)
        return """
            public struct Client {
                \(raw: properties)
                public init(\(raw: parameters)) {
                    \(raw: assignments)
                }
                \(raw: remote)
            }
            """
    }

    private static func composedRemote(
        _ scopes: [Scope]
    ) -> String {
        let properties = scopes.map { scope in
            "public let \(scope.name): \(scope.domain).Client.Remote<External>"
        }.joined(separator: " ")
        let parameters = scopes.map { scope in
            "\(scope.name): \(scope.domain).Client.Remote<External>"
        }.joined(separator: ", ")
        let assignments = scopes.map { scope in
            "self.\(scope.name) = \(scope.name)"
        }.joined(separator: "; ")
        return """
            public struct Remote<External: Swift.Error> {
                \(properties)
                public init(\(parameters)) {
                    \(assignments)
                }
            }
            """
    }

    private static func diagnostics(
        node: some SyntaxProtocol,
        message: String
    ) -> DiagnosticsError {
        DiagnosticsError(
            diagnostics: [
                .init(
                    node: node,
                    message: Message(message)
                )
            ]
        )
    }
}
