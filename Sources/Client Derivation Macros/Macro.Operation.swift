import SwiftSyntax
import SwiftSyntaxBuilder

extension Macro {
    struct Operation {
        let failure: TypeSyntax
        let name: TokenSyntax
        let output: TypeSyntax
        let parameters: FunctionParameterListSyntax

        init(_ member: MemberBlockItemSyntax) throws(Diagnostic) {
            guard let declaration = member.decl.as(FunctionDeclSyntax.self) else {
                throw .init(
                    message: "Client supports protocol function requirements only.",
                    node: Syntax(member.decl)
                )
            }
            guard case .identifier = declaration.name.tokenKind else {
                throw .init(
                    message: "Client requires an identifier operation name.",
                    node: Syntax(declaration.name)
                )
            }
            guard declaration.genericParameterClause == nil,
                  declaration.genericWhereClause == nil
            else {
                throw .init(
                    message: "Client cannot store a generic operation as one arrow.",
                    node: Syntax(declaration)
                )
            }
            guard declaration.attributes.isEmpty,
                  declaration.modifiers.isEmpty
            else {
                throw .init(
                    message: "Client cannot preserve operation attributes, ownership, or isolation modifiers.",
                    node: declaration.attributes.isEmpty
                        ? Syntax(declaration.modifiers)
                        : Syntax(declaration.attributes)
                )
            }

            let effects = declaration.signature.effectSpecifiers
            guard effects?.asyncSpecifier != nil,
                  effects?.asyncSpecifier?.tokenKind != .keyword(.reasync)
            else {
                throw .init(
                    message: "Client requires an asynchronous operation.",
                    node: Syntax(declaration.signature)
                )
            }
            if let effects,
               effects.throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows)
            {
                throw .init(
                    message: "Client cannot store rethrows as an arrow effect.",
                    node: Syntax(effects)
                )
            }
            if let clause = effects?.throwsClause, clause.type == nil {
                throw .init(
                    message: "Client requires a precise typed throws(Failure) clause.",
                    node: Syntax(clause)
                )
            }
            if let failure = effects?.throwsClause?.type,
               failure.as(SomeOrAnyTypeSyntax.self) != nil
                || Self.containsOpaqueOrSelfType(failure)
            {
                throw .init(
                    message: "Client requires a concrete failure type, not an "
                        + "opaque, existential, or Self-dependent error.",
                    node: Syntax(failure)
                )
            }

            let parameters = declaration.signature.parameterClause.parameters
            for parameter in parameters {
                guard parameter.attributes.isEmpty,
                      parameter.modifiers.isEmpty,
                      parameter.defaultValue == nil,
                      parameter.ellipsis == nil,
                      parameter.type.as(AttributedTypeSyntax.self) == nil,
                      !Self.containsOpaqueOrSelfType(parameter.type),
                      parameter.firstName.text != "_" || parameter.secondName != nil,
                      parameter.secondName?.text != "_"
                else {
                    throw .init(
                        message: "Client requires concrete named parameters "
                            + "without opaque or Self-dependent types, "
                            + "attributes, ownership, defaults, or variadics.",
                        node: Syntax(parameter)
                    )
                }
            }
            if let returnType = declaration.signature.returnClause?.type,
               returnType.as(AttributedTypeSyntax.self) != nil
                || Self.containsOpaqueOrSelfType(returnType)
            {
                throw .init(
                    message: "Client cannot preserve an attributed, opaque, "
                        + "Self-dependent, or ownership-qualified result.",
                    node: Syntax(returnType)
                )
            }

            self.parameters = parameters
            name = declaration.name
            output = declaration.signature.returnClause?.type ?? Self.void
            failure = effects?.throwsClause?.type ?? TypeSyntax(
                MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: .identifier("Swift")),
                    period: .periodToken(),
                    name: .identifier("Never")
                )
            )
        }

        var property: String {
            "public let \(name.trimmedDescription): \(arrow)"
        }

        var parameter: String {
            "\(name.trimmedDescription): \(arrow)"
        }

        var assignment: String {
            "self.\(name.trimmedDescription) = \(name.trimmedDescription)"
        }

        var closure: String {
            "\(name.trimmedDescription): @escaping \(signature)"
        }

        var implementation: String {
            if parameters.count == 1 {
                return "self.\(name.trimmedDescription) = .init(run: \(name.trimmedDescription))"
            }
            let parameter = parameters.isEmpty ? "_" : "input"
            let arguments = parameters.indices.map { index in
                let parameter = parameters[index]
                if parameter.firstName.text == "_" {
                    return "input.\(index)"
                }
                return "input.\(parameter.firstName.trimmedDescription)"
            }.joined(separator: ", ")
            let invocation = "\(prefix)\(name.trimmedDescription)(\(arguments))"
            let effect = Self.isNever(failure)
                ? ""
                : " throws(\(failure.trimmedDescription))"
            return "self.\(name.trimmedDescription) = .init(run: { \(parameter)\(effect) in \(invocation) })"
        }

        var remote: String {
            "public let \(name.trimmedDescription): \(transport)"
        }

        var external: String {
            "\(name.trimmedDescription): \(transport)"
        }

        private var arrow: String {
            "Client::Client<\(input.trimmedDescription), \(output.trimmedDescription), \(failure.trimmedDescription)>"
        }

        private var signature: String {
            let inputs = parameters.map(\.type.trimmedDescription)
                .joined(separator: ", ")
            let effect = Self.isNever(failure)
                ? ""
                : " throws(\(failure.trimmedDescription))"
            return "(\(inputs)) async\(effect) -> \(output.trimmedDescription)"
        }

        private var input: TypeSyntax {
            if parameters.isEmpty {
                return Self.void
            }
            if parameters.count == 1 {
                return parameters[parameters.startIndex].type
            }
            return TypeSyntax(
                TupleTypeSyntax(
                    elements: TupleTypeElementListSyntax {
                        for index in parameters.indices {
                            if parameters[index].firstName.text == "_" {
                                TupleTypeElementSyntax(
                                    type: parameters[index].type,
                                    trailingComma: index == parameters.indices.last
                                        ? nil
                                        : .commaToken(trailingTrivia: .space)
                                )
                            } else {
                                TupleTypeElementSyntax(
                                    firstName: parameters[index].firstName,
                                    colon: .colonToken(trailingTrivia: .space),
                                    type: parameters[index].type,
                                    trailingComma: index == parameters.indices.last
                                        ? nil
                                        : .commaToken(trailingTrivia: .space)
                                )
                            }
                        }
                    }
                )
            )
        }

        private var prefix: String {
            Self.isNever(failure) ? "await " : "try await "
        }

        private var transport: String {
            "Client::Client<\(input.trimmedDescription), "
                + "\(output.trimmedDescription), "
                + "Either<External, \(failure.trimmedDescription)>>"
        }

        private static var void: TypeSyntax {
            TypeSyntax(
                MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: .identifier("Swift")),
                    period: .periodToken(),
                    name: .identifier("Void")
                )
            )
        }

        private static func isNever(_ type: TypeSyntax) -> Bool {
            if let identifier = type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text == "Never"
            }
            guard let member = type.as(MemberTypeSyntax.self),
                  member.name.text == "Never",
                  let module = member.baseType.as(IdentifierTypeSyntax.self)
            else {
                return false
            }
            return module.name.text == "Swift"
        }

        private static func containsOpaqueOrSelfType(_ type: TypeSyntax) -> Bool {
            type.tokens(viewMode: .sourceAccurate).contains { token in
                token.tokenKind == .keyword(.some)
                    || token.tokenKind == .keyword(.Self)
            }
        }
    }
}
