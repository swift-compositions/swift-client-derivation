public import Client_Derivation
public import Client
public import Either
import Testing

extension Product {
    @Client
    package protocol Signature {
        func ping() async
        func combine(first: Int, second: Int) async -> Int
    }
}

@Test
func `client derives a product of arrows`() async {
    var pings = 0
    let client = Product.Client(
        ping: { pings += 1 },
        combine: +
    )

    await client.ping(())
    #expect(pings == 1)
    #expect(await client.combine((first: 2, second: 3)) == 5)
}
