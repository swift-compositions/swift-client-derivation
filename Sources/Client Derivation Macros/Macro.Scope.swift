import SwiftSyntax

extension Macro {
    struct Scope {
        let name: String
        let type: String
        let domain: String

        init(_ member: MemberBlockItemSyntax) throws(Diagnostic) {
            guard let declaration = member.decl.as(VariableDeclSyntax.self),
                  declaration.bindings.count == 1,
                  let binding = declaration.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  let type = binding.typeAnnotation?.type,
                  let client = type.as(MemberTypeSyntax.self),
                  client.name.text == "Client",
                  binding.initializer == nil
            else {
                throw .init(
                    message: "Client requires each composed scope to be one get-only client property.",
                    node: Syntax(member.decl)
                )
            }
            if let accessor = binding.accessorBlock,
               case .accessors(let accessors) = accessor.accessors,
               accessors.contains(where: {
                   $0.accessorSpecifier.tokenKind != .keyword(.get)
               })
            {
                throw .init(
                    message: "Client requires a get-only composed client property.",
                    node: Syntax(accessor)
                )
            }
            name = identifier.identifier.text
            self.type = type.trimmedDescription
            domain = client.baseType.trimmedDescription
        }
    }
}
