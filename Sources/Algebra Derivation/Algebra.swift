@attached(peer, names: named(Client))
public macro Algebra() = #externalMacro(
    module: "Algebra_Derivation_Macros",
    type: "AlgebraMacro"
)
