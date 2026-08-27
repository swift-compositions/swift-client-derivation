import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import Witness_Derivation_Core

public struct ClientMacro: PeerMacro {
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
                        message: ClientMessage(
                            "Client attaches to a protocol declaration only."
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
                        message: ClientMessage(
                            "Client derives a protocol named Signature."
                        )
                    )
                ]
            )
        }

        if protocolDeclaration.memberBlock.members.allSatisfy({
            $0.decl.is(VariableDeclSyntax.self)
        }) {
            do {
                var expansion = [try composedClient(protocolDeclaration)]
                if hasCalls(protocolDeclaration) {
                    expansion.append(try composedRemote(protocolDeclaration))
                }
                return expansion
            } catch let message as ClientScopeError {
                throw DiagnosticsError(
                    diagnostics: [
                        .init(
                            node: message.node,
                            message: ClientMessage(message.message)
                        )
                    ]
                )
            }
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
        let call = hasCalls(protocolDeclaration)
            ? TypeSyntax(IdentifierTypeSyntax(name: .identifier("Call")))
            : nil
        do {
            var expansion = try WitnessDerivation.expansion(
                of: protocolDeclaration,
                configuration: .init(
                    name: .identifier("Client"),
                    access: .public,
                    storage: .client(client),
                    call: call
                )
            )
            if call != nil {
                expansion.append(try remoteClient(protocolDeclaration))
            }
            return expansion
        } catch let error as WitnessDerivation.Diagnostic {
            throw DiagnosticsError(
                diagnostics: [
                    .init(
                        node: error.node,
                        message: ClientMessage(error.message)
                    )
                ]
            )
        } catch let message as ClientScopeError {
            throw DiagnosticsError(
                diagnostics: [
                    .init(
                        node: message.node,
                        message: ClientMessage(message.message)
                    )
                ]
            )
        }
    }

    private static func hasCalls(_ declaration: ProtocolDeclSyntax) -> Bool {
        declaration.attributes.contains(where: { element in
            guard case .attribute(let attribute) = element,
                  let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name
            else {
                return false
            }
            return name.text == "Calls"
        })
    }

    private static func composedClient(
        _ declaration: ProtocolDeclSyntax
    ) throws -> DeclSyntax {
        let scopes = try declaration.memberBlock.members.map(ClientScope.init)
        let properties = scopes.map { scope in
            "public let \(scope.name): \(scope.type)"
        }.joined(separator: " ")
        let parameters = scopes.map { scope in
            "\(scope.name): \(scope.type)"
        }.joined(separator: ", ")
        let assignments = scopes.map { scope in
            "self.\(scope.name) = \(scope.name)"
        }.joined(separator: "; ")
        let interpretsCalls = declaration.attributes.contains { element in
            guard case .attribute(let attribute) = element,
                  let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name
            else { return false }
            return name.text == "Calls"
        }
        let interpreter: String
        if interpretsCalls {
            let branches = scopes.map { scope in
                "case .\(scope.name)(let call): return .\(scope.name)(await \(scope.name)(call))"
            }.joined(separator: " ")
            interpreter = "public func callAsFunction(_ call: Call) async -> Call.Result { switch call { \(branches) } }"
        } else {
            interpreter = ""
        }
        return """
            public struct Client {
                \(raw: properties)
                public init(\(raw: parameters)) { \(raw: assignments) }
                \(raw: interpreter)
            }
            """
    }

    private static func composedRemote(
        _ declaration: ProtocolDeclSyntax
    ) throws -> DeclSyntax {
        let scopes = try declaration.memberBlock.members.map(ClientScope.init)
        let properties = scopes.map { scope in
            "public let \(scope.name): \(scope.domain).Client.Remote<External>"
        }.joined(separator: " ")
        let assignments = scopes.map { scope in
            """
            self.\(scope.name) = .init(
                Client::Client<\(scope.domain).Call, \(scope.domain).Call.Result, External>(
                    run: { child throws(External) in
                        let result = try await call(.\(scope.name)(child))
                        guard case .\(scope.name)(let child) = result else {
                            fatalError("Call result branch mismatch")
                        }
                        return child
                    }
                )
            )
            """
        }.joined(separator: " ")
        return """
            extension Client {
                public struct Remote<External: Swift.Error> {
                    \(raw: properties)
                    public init(
                        _ call: Client::Client<Call, Call.Result, External>
                    ) {
                        \(raw: assignments)
                    }
                }
            }
            """
    }

    private static func remoteClient(
        _ declaration: ProtocolDeclSyntax
    ) throws -> DeclSyntax {
        let operations = try declaration.memberBlock.members.map(ClientOperation.init)
        let methods = operations.map(\.remoteMethod).joined(separator: " ")
        return """
            extension Client {
                public struct Remote<External: Swift.Error> {
                    private let call: Client::Client<Call, Call.Result, External>
                    public init(
                        _ call: Client::Client<Call, Call.Result, External>
                    ) {
                        self.call = call
                    }
                    \(raw: methods)
                }
            }
            """
    }
}

private struct ClientScope {
    let name: String
    let type: String
    let domain: String

    init(_ member: MemberBlockItemSyntax) throws {
        guard let declaration = member.decl.as(VariableDeclSyntax.self),
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type,
              let client = type.as(MemberTypeSyntax.self),
              client.name.text == "Client",
              binding.initializer == nil
        else {
            throw ClientScopeError(
                message: "Client requires each composed scope to be one get-only client property.",
                node: Syntax(member.decl)
            )
        }
        if let accessor = binding.accessorBlock,
           case .accessors(let accessors) = accessor.accessors,
           accessors.contains(where: { $0.accessorSpecifier.tokenKind != .keyword(.get) })
        {
            throw ClientScopeError(
                message: "Client requires a get-only composed client property.",
                node: Syntax(accessor)
            )
        }
        self.name = identifier.identifier.text
        self.type = type.trimmedDescription
        self.domain = client.baseType.trimmedDescription
    }
}

private struct ClientOperation {
    let declaration: FunctionDeclSyntax
    let failure: String?
    let name: String
    let output: String
    let arguments: [String]

    init(_ member: MemberBlockItemSyntax) throws {
        guard let declaration = member.decl.as(FunctionDeclSyntax.self) else {
            throw ClientScopeError(
                message: "Client supports function requirements or composed client properties only.",
                node: Syntax(member.decl)
            )
        }
        self.declaration = declaration
        name = declaration.name.text
        let parameters = declaration.signature.parameterClause.parameters
        arguments = parameters.map { ($0.secondName ?? $0.firstName).text }
        output = declaration.signature.returnClause?.type.trimmedDescription ?? "Swift.Void"
        failure = declaration.signature.effectSpecifiers?.throwsClause?.type?.trimmedDescription
    }

    var remoteMethod: String {
        let parameters = declaration.signature.parameterClause.parameters.trimmedDescription
        let callArguments = declaration.signature.parameterClause.parameters.enumerated().map {
            index, parameter in
            let value = arguments[index]
            return parameter.firstName.text == "_"
                ? value
                : "\(parameter.firstName.text): \(value)"
        }.joined(separator: ", ")
        let remoteFailure = failure.map { "Either<External, \($0)>" } ?? "External"
        let retrieve: String
        if let failure {
            retrieve = """
                let result: Call.Result
                do throws(External) {
                    result = try await call(.\(name)(\(callArguments)))
                } catch {
                    throw Either<External, \(failure)>.left(error)
                }
                guard case .\(name)(let outcome) = result else {
                    fatalError("Call result branch mismatch")
                }
                switch outcome {
                case .success(let value): return value
                case .failure(let refusal): throw .right(refusal)
                }
                """
        } else {
            retrieve = """
                let result = try await call(.\(name)(\(callArguments)))
                guard case .\(name)(let value) = result else {
                    fatalError("Call result branch mismatch")
                }
                return value
                """
        }
        return """
            public func \(name)(\(parameters)) async throws(\(remoteFailure)) -> \(output) {
                \(retrieve)
            }
            """
    }
}

private struct ClientScopeError: Swift.Error {
    let message: String
    let node: Syntax
}
