public import SwiftSyntax
public import Signature_Derivation_Core
import Product_Derivation_Core
import SwiftSyntaxBuilder

extension Client {
    public enum Derivation {
        public static func peers(of signature: Signature.Analysis) -> [DeclSyntax] {
            let access = signature.product.access.map { "\($0.name.text) " } ?? ""
            return [
                client(of: signature, access: access),
                replying(of: signature, access: access),
                replies(of: signature, access: access),
            ]
        }

        private static func client(of signature: Signature.Analysis, access: String) -> DeclSyntax {
            let owner = signature.owner.trimmedDescription
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
            let convenience = """
                    \(access)static func client<
                        Router: Coder::Coder.`Protocol`,
                        Replies: \(owner).Replying,
                        Interpretation: Client_Derivation::Interpretation
                    >(
                        routing router: Router,
                        replying replies: Replies,
                        over interpretation: Interpretation
                    ) -> Self
                    where
                        Router.Input == Interpretation.Message,
                        Router.Output == \(owner).Call,
                        Router.Buffer == Interpretation.Message,
                        Router.Failure == Interpretation.Routing,
                        Replies.Reply == Interpretation.Reply,
                        Replies.Failure == Interpretation.Routing,
                        External == Interpretation.External {
                        replies.client(routing: router, over: interpretation) { $0 }
                    }
                """
            let members = (storedArrows + storedChildren + [initializer] + forwarding + [convenience])
                .joined(separator: "\n\n")
            return DeclSyntax(stringLiteral: """
                \(access)struct Client<External: Swift.Error> {
                \(members)
                }
                """)
        }

        private static func replying(of signature: Signature.Analysis, access: String) -> DeclSyntax {
            let owner = signature.owner.trimmedDescription
            return DeclSyntax(stringLiteral: """
                \(access)protocol Replying {
                    associatedtype Reply

                    associatedtype Failure: Swift.Error

                    func client<
                        Route: ~Copyable,
                        Router: Coder::Coder.`Protocol`,
                        Interpretation: Client_Derivation::Interpretation
                    >(
                        routing router: Router,
                        over interpretation: Interpretation,
                        embedding embed: @escaping (\(owner).Call) -> Route
                    ) -> \(owner).Client<Interpretation.External>
                    where
                \(requirements)
                }
                """)
        }

        private static func replies(of signature: Signature.Analysis, access: String) -> DeclSyntax {
            let owner = signature.owner.trimmedDescription
            let leaves = signature.coordinates.map { coordinate in
                (
                    label: coordinate.name.text,
                    parameter: "\(coordinate.symbol.text)Reply",
                    bound: "Coder::Coding<Reply, \(reply(of: coordinate, owner: owner)), Reply, Failure>"
                )
            }
            let children = signature.children.map { child in
                let name = child.name.text
                return (
                    label: name,
                    parameter: "\(name.prefix(1).uppercased())\(name.dropFirst())Replies",
                    bound: "\(child.domain.trimmedDescription).Replying"
                )
            }
            let parameters = (
                ["Reply", "Failure: Swift.Error"]
                    + (leaves + children).map { "\($0.parameter): \($0.bound)" }
            ).map { "    \($0)" }.joined(separator: ",\n")
            let constraints = children.flatMap { child in
                [
                    "\(child.parameter).Reply == Reply",
                    "\(child.parameter).Failure == Failure",
                ]
            }
            let structWhere = constraints.isEmpty
                ? ""
                : "\nwhere\n" + constraints.map { "    \($0)" }.joined(separator: ",\n")
            let storage = (leaves + children).map {
                "    \(access)let \($0.label): \($0.parameter)"
            }
            let initializerParameters = (leaves + children).map {
                "\($0.label): \($0.parameter)"
            }.joined(separator: ", ")
            let assignments = (leaves + children).map {
                "        self.\($0.label) = \($0.label)"
            }
            let initializer = """
                    \(access)init(\(initializerParameters)) {
                \(assignments.joined(separator: "\n"))
                    }
                """
            let arrows = signature.coordinates.map { coordinate in
                "            \(coordinate.name.text): interpretation.arrow(\(owner).Operations.\(coordinate.symbol.trimmedDescription).self, requesting: router, replying: \(coordinate.name.text)) { embed(\(owner).Call.\(coordinate.name.text)($0)) }"
            } + signature.children.map { child in
                "            \(child.name.text): \(child.name.text).client(routing: router, over: interpretation) { embed(\(owner).Call.\(child.name.text)($0)) }"
            }
            let fold = """
                    \(access)func client<
                        Route: ~Copyable,
                        Router: Coder::Coder.`Protocol`,
                        Interpretation: Client_Derivation::Interpretation
                    >(
                        routing router: Router,
                        over interpretation: Interpretation,
                        embedding embed: @escaping (\(owner).Call) -> Route
                    ) -> \(owner).Client<Interpretation.External>
                    where
                \(requirements) {
                        .init(
                \(arrows.joined(separator: ",\n"))
                        )
                    }
                """
            let members = (storage + [initializer, fold]).joined(separator: "\n\n")
            return DeclSyntax(stringLiteral: """
                \(access)struct Replies<
                \(parameters)
                >: \(owner).Replying\(structWhere) {
                \(members)
                }
                """)
        }

        private static var requirements: String {
            [
                "Router.Input == Interpretation.Message",
                "Router.Output == Route",
                "Router.Buffer == Interpretation.Message",
                "Router.Failure == Interpretation.Routing",
                "Reply == Interpretation.Reply",
                "Failure == Interpretation.Routing",
            ].map { "            \($0)" }.joined(separator: ",\n")
        }

        private static func reply(of coordinate: Signature.Analysis.Coordinate, owner: String) -> String {
            let symbol = "\(owner).Operations.\(coordinate.symbol.trimmedDescription)"
            return "Either::Either<\(symbol).Failure, \(symbol).Output>"
        }

        private static func failure(of coordinate: Signature.Analysis.Coordinate) -> String {
            "Either<External, \(coordinate.failure.trimmedDescription)>"
        }

        private static func arrow(of coordinate: Signature.Analysis.Coordinate) -> String {
            "Client::Client<\(coordinate.input.trimmedDescription), \(coordinate.output.trimmedDescription), \(failure(of: coordinate))>"
        }
    }
}
