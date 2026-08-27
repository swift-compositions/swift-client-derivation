import SwiftDiagnostics

extension Macro {
    struct Message: DiagnosticMessage {
        let message: String
        let diagnosticID = MessageID(
            domain: "ClientDerivation",
            id: "unsupported-signature"
        )
        let severity = DiagnosticSeverity.error

        init(_ message: String) {
            self.message = message
        }
    }
}
