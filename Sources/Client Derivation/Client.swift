@_exported import Client
@_exported import Coder
@_exported import Either
@_exported import Operation
@_exported import Parser
@_exported import Serializer

@attached(peer, names: named(Client), named(Replying), named(Replies))
public macro Client() = #externalMacro(
    module: "Client_Derivation_Macros",
    type: "Macro"
)
