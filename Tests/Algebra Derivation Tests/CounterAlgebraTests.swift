import Algebra_Derivation
import Client
import Testing

public enum CounterAlgebraFixture {
    @Algebra
    package protocol Signature {
        func increment(limit: Int) async throws(CounterAlgebraFailure) -> Int
    }
}

@Test
func algebraDerivesTypedRefusalClientArrow() async throws {
    let client = CounterAlgebraFixture.Client(
        increment: { limit throws(CounterAlgebraFailure) in
            guard limit > 0 else {
                throw .limit
            }
            return limit + 1
        }
    )
    #expect(try await client.increment(limit: 2) == 3)
    await #expect(throws: CounterAlgebraFailure.limit) {
        try await client.increment(limit: 0)
    }
}
