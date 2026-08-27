import Client_Derivation
import Client
import Testing

public enum ProductClientFixture {
    @Client
    package protocol Signature {
        func ping() async
        func combine(first: Int, second: Int) async -> Int
    }
}

@Test
func clientDerivesAProductOfArrows() async {
    var pings = 0
    let client = ProductClientFixture.Client(
        ping: { pings += 1 },
        combine: +
    )

    await client.ping()
    #expect(pings == 1)
    #expect(await client.combine(first: 2, second: 3) == 5)
}
