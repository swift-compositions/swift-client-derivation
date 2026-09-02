public import Client_Derivation
public import Client
public import Either
import Testing

extension Greeting {
    @Client
    package protocol Signature {
        func greet(_ name: String) async -> String
    }
}

@Test
func `client derives an infallible arrow`() async {
    let client = Greeting.Client(
        greet: { "Hello, \($0)" }
    )
    #expect(await client.greet("Ada") == "Hello, Ada")
}

@Test
func `client derives a pointwise remote product`() async throws {
    let remote = Greeting.Client.Remote<Counter.Error>(
        greet: .init(run: { name in name })
    )

    #expect(try await remote.greet("Ada") == "Ada")
}
