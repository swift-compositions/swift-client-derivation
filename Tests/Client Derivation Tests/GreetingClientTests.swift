import Client_Derivation
import Client
import Testing

public enum GreetingClientFixture {
    @Client
    package protocol Signature {
        func greet(_ name: String) async -> String
    }
}

@Test
func clientDerivesInfallibleArrow() async {
    let client = GreetingClientFixture.Client(
        greet: { "Hello, \($0)" }
    )
    #expect(await client.greet("Ada") == "Hello, Ada")
}
