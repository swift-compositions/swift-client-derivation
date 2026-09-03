public import SwiftSyntax
public import Signature_Derivation_Core
import SwiftSyntaxBuilder

public enum Derivation {
    public static func peers(of signature: Signature) -> [DeclSyntax] {
        let access = signature.product.access.map { "\($0.name.text) " } ?? ""
        let storedArrows = signature.coordinates.map { coordinate in
            "    private let _\(coordinate.name.text): \(arrow(of: coordinate))"
        }
        let storedChildren = signature.children.map { child in
            "    \(access)let \(child.name.text): \(child.domain.trimmedDescription).Client<External>"
        }
        let parameters = signature.coordinates.map { coordinate in
            "\(coordinate.name.text): \(arrow(of: coordinate))"
        } + signature.children.map { child in
            "\(child.name.text): \(child.domain.trimmedDescription).Client<External>"
        }
        let assignments = signature.coordinates.map { coordinate in
            "        self._\(coordinate.name.text) = \(coordinate.name.text)"
        } + signature.children.map { child in
            "        self.\(child.name.text) = \(child.name.text)"
        }
        let forwarding = signature.coordinates.map { coordinate in
            """
                \(access)func \(coordinate.name.text)\(coordinate.declaration.signature.parameterClause.trimmedDescription) async throws(\(failure(of: coordinate))) -> \(coordinate.output.trimmedDescription) {
                    try await self._\(coordinate.name.text)(\(coordinate.inputExpression.trimmedDescription))
                }
            """
        }
        let initializer = """
                \(access)init(\(parameters.joined(separator: ", "))) {
            \(assignments.joined(separator: "\n"))
                }
            """
        let members = (storedArrows + storedChildren + [initializer] + forwarding)
            .joined(separator: "\n\n")
        return [DeclSyntax(stringLiteral: """
            \(access)struct Client<External: Swift.Error> {
            \(members)
            }
            """)]
    }

    private static func failure(of coordinate: Signature.Coordinate) -> String {
        "Either<External, \(coordinate.failure.trimmedDescription)>"
    }

    private static func arrow(of coordinate: Signature.Coordinate) -> String {
        "Client::Client<\(coordinate.input.trimmedDescription), \(coordinate.output.trimmedDescription), \(failure(of: coordinate))>"
    }
}
