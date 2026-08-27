import Client_Derivation
import Client
import Testing

public enum CounterClientFixture {
    @Client
    package protocol Signature {
        func increment(limit: Int) async throws(CounterClientFailure) -> Int
    }
}

@Test
func clientDerivesTypedRefusalArrow() async throws {
    let client = CounterClientFixture.Client(
        increment: { limit throws(CounterClientFailure) in
            guard limit > 0 else {
                throw .limit
            }
            return limit + 1
        }
    )
    #expect(try await client.increment(limit: 2) == 3)
    await #expect(throws: CounterClientFailure.limit) {
        try await client.increment(limit: 0)
    }
}
