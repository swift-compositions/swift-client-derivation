import Client_Derivation
import Signature_Derivation
import Testing

private enum Greeting {
    struct Name: Equatable {
        var value: String
    }

    struct Message: Equatable {
        var value: String
    }

    @Signature
    @Client
    protocol `Protocol` {
        func greet(_ name: Name) async -> Message
    }
}

private enum Counter {
    struct Limit {
        var value: Int
    }

    struct Value: Equatable {
        var value: Int
    }

    enum Error: Swift.Error, Equatable {
        case exceeded
    }

    @Signature
    @Client
    protocol `Protocol` {
        func increment(limit: Limit) async throws(Error) -> Value
    }
}

private enum Example {
    @Signature
    @Client
    protocol `Protocol` {
        associatedtype Greeting: Client_Derivation_Tests::Greeting.`Protocol`
        associatedtype Counter: Client_Derivation_Tests::Counter.`Protocol`

        var greeting: Greeting { get }
        var counter: Counter { get }
    }
}

private enum Transport: Swift.Error, Equatable {
    case unreachable
}

@Suite
private struct `Consumer Tests` {
    @Test
    func `a leaf client lifts every operation failure into the external coproduct`() async throws {
        let client = Greeting.Client<Transport>(
            greet: .init { name throws(Either<Transport, Never>) in
                .init(value: "Hello, \(name.value)!")
            }
        )

        #expect(try await client.greet(.init(value: "Blob")) == .init(value: "Hello, Blob!"))
    }

    @Test
    func `a leaf client preserves labels and the domain refusal branch`() async {
        let client = Counter.Client<Transport>(
            increment: .init { limit throws(Either<Transport, Counter.Error>) in
                guard limit.value < 10 else { throw .right(.exceeded) }
                return .init(value: limit.value + 1)
            }
        )

        await #expect(throws: Either<Transport, Counter.Error>.right(.exceeded)) {
            try await client.increment(limit: .init(value: 10))
        }
    }

    @Test
    func `a root client composes child clients over one external failure`() async throws {
        let client = Example.Client<Transport>(
            greeting: .init(greet: .init { name throws(Either<Transport, Never>) in .init(value: "Hi \(name.value)") }),
            counter: .init(increment: .init { _ throws(Either<Transport, Counter.Error>) in throw .left(.unreachable) })
        )

        #expect(try await client.greeting.greet(.init(value: "Blob")) == .init(value: "Hi Blob"))
        await #expect(throws: Either<Transport, Counter.Error>.left(.unreachable)) {
            try await client.counter.increment(limit: .init(value: 1))
        }
    }
}
