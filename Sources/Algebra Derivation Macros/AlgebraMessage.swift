import SwiftDiagnostics

struct AlgebraMessage: DiagnosticMessage {
    let message: String
    let diagnosticID = MessageID(
        domain: "AlgebraDerivation",
        id: "unsupported-signature"
    )
    let severity = DiagnosticSeverity.error

    init(_ message: String) {
        self.message = message
    }
}
