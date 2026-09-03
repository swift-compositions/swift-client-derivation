@_exported import Client
@_exported import Either

@attached(peer, names: named(Client))
public macro Client() = #externalMacro(
    module: "Client_Derivation_Macros",
    type: "Macro"
)
