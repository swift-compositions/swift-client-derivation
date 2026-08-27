import Client_Derivation
import Client
import Testing

extension Counter {
    @Client
    package protocol Signature {
        func increment(limit: Int) async throws(Error) -> Int
    }
}

@Test
func `client derives a typed refusal arrow`() async throws {
    let client = Counter.Client(
        increment: { limit throws(Counter.Error) in
            guard limit > 0 else {
                throw .limit
            }
            return limit + 1
        }
    )
    #expect(try await client.increment(2) == 3)
    await #expect(throws: Counter.Error.limit) {
        try await client.increment(0)
    }
}
