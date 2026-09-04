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
        func reset() async
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
    case malformed
}

private enum Mismatch: Swift.Error, Equatable {
    case absent
    case malformed
}

private struct Record: Equatable, Restorable {
    typealias Checkpoint = Record

    var path: [String]
    var body: String?
}

private struct Segment<Index: Operation.Symbol>: Coding where Index.Input: Copyable & Escapable {
    typealias Input = Record
    typealias Output = Operation.Application<Index>
    typealias Buffer = Record
    typealias Failure = Mismatch

    let name: String
    let encode: (Index.Input) -> String?
    let decode: (String?) -> Index.Input?

    borrowing func parse(_ input: inout Record) throws(Mismatch) -> Operation.Application<Index> {
        guard input.path.first == name else { throw .absent }
        guard let value = decode(input.body) else { throw .malformed }
        input.path.removeFirst()
        input.body = nil
        return .init(value)
    }

    borrowing func serialize(
        _ output: borrowing Operation.Application<Index>,
        into buffer: inout Record
    ) throws(Mismatch) {
        buffer.path.append(name)
        buffer.body = encode(output.input)
    }
}

private struct Outcome<Refusal: Swift.Error, Value>: Coding {
    typealias Input = String
    typealias Output = Either<Refusal, Value>
    typealias Buffer = String
    typealias Failure = Mismatch

    let decode: (String) -> Either<Refusal, Value>?
    let encode: (Either<Refusal, Value>) -> String

    borrowing func parse(_ input: inout String) throws(Mismatch) -> Either<Refusal, Value> {
        guard let outcome = decode(input) else { throw .malformed }
        input = ""
        return outcome
    }

    borrowing func serialize(
        _ output: borrowing Either<Refusal, Value>,
        into buffer: inout String
    ) throws(Mismatch) {
        buffer = encode(output)
    }
}

private struct Wire: Interpretation {
    typealias External = Transport
    typealias Routing = Mismatch
    typealias Message = Record
    typealias Reply = String

    let respond: (Record) throws(Transport) -> String

    var blank: Record {
        Record(path: [], body: nil)
    }

    func external(_ failure: Mismatch) -> Transport {
        .malformed
    }

    func send(_ message: Record) async throws(Transport) -> String {
        try respond(message)
    }
}

private var router: Example.Call.Router<
    Record,
    Mismatch,
    Greeting.Call.Router<Record, Mismatch, Segment<Greeting.Operations.Greet>>,
    Counter.Call.Router<
        Record,
        Mismatch,
        Segment<Counter.Operations.Increment>,
        Segment<Counter.Operations.Reset>
    >
> {
    Example.Call.Router(
        absent: .absent,
        greeting: Greeting.Call.Router(
            absent: .absent,
            greet: Segment<Greeting.Operations.Greet>(
                name: "greet",
                encode: { $0.value },
                decode: { $0.map(Greeting.Name.init(value:)) }
            )
        ),
        counter: Counter.Call.Router(
            absent: .absent,
            increment: Segment<Counter.Operations.Increment>(
                name: "increment",
                encode: { String($0.value) },
                decode: { $0.flatMap { Int($0) }.map(Counter.Limit.init(value:)) }
            ),
            reset: Segment<Counter.Operations.Reset>(
                name: "reset",
                encode: { _ in nil },
                decode: { _ in () }
            )
        )
    )
}

private var replies: Example.Replies<
    String,
    Mismatch,
    Greeting.Replies<String, Mismatch, Outcome<Never, Greeting.Message>>,
    Counter.Replies<String, Mismatch, Outcome<Counter.Error, Counter.Value>, Outcome<Never, Void>>
> {
    Example.Replies(
        greeting: Greeting.Replies(
            greet: Outcome<Never, Greeting.Message>(
                decode: { .right(.init(value: $0)) },
                encode: { $0.value.value }
            )
        ),
        counter: Counter.Replies(
            increment: Outcome<Counter.Error, Counter.Value>(
                decode: { text in
                    if text == "exceeded" { return .left(.exceeded) }
                    return Int(text).map { .right(.init(value: $0)) }
                },
                encode: { outcome in
                    switch outcome {
                    case .left(.exceeded): "exceeded"
                    case .right(let value): String(value.value)
                    }
                }
            ),
            reset: Outcome<Never, Void>(
                decode: { $0.isEmpty ? .right(()) : nil },
                encode: { _ in "" }
            )
        )
    )
}

private func serve(_ record: Record) throws(Transport) -> String {
    switch record.path.first {
    case "greet":
        return "Hello, \(record.body ?? "")!"
    case "increment":
        guard let limit = record.body.flatMap({ Int($0) }) else { throw .malformed }
        return limit < 10 ? String(limit + 1) : "exceeded"
    case "reset":
        return record.body == nil ? "" : "unexpected"
    default:
        throw .unreachable
    }
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
            },
            reset: .init { _ throws(Either<Transport, Never>) in }
        )

        await #expect(throws: Either<Transport, Counter.Error>.right(.exceeded)) {
            try await client.increment(limit: .init(value: 10))
        }
    }

    @Test
    func `a root client composes child clients over one external failure`() async throws {
        let client = Example.Client<Transport>(
            greeting: .init(greet: .init { name throws(Either<Transport, Never>) in .init(value: "Hi \(name.value)") }),
            counter: .init(
                increment: .init { _ throws(Either<Transport, Counter.Error>) in throw .left(.unreachable) },
                reset: .init { _ throws(Either<Transport, Never>) in }
            )
        )

        #expect(try await client.greeting.greet(.init(value: "Blob")) == .init(value: "Hi Blob"))
        await #expect(throws: Either<Transport, Counter.Error>.left(.unreachable)) {
            try await client.counter.increment(limit: .init(value: 1))
        }
    }

    @Test
    func `a derived client routes a request and decodes a successful reply`() async throws {
        let wire = Wire(respond: serve)
        let client = Example.Client.client(routing: router, replying: replies, over: wire)

        #expect(try await client.greeting.greet(.init(value: "Blob")) == .init(value: "Hello, Blob!"))
        #expect(try await client.counter.increment(limit: .init(value: 2)) == .init(value: 3))
    }

    @Test
    func `a derived client surfaces a refusal on the right`() async {
        let wire = Wire(respond: serve)
        let client = Example.Client.client(routing: router, replying: replies, over: wire)

        await #expect(throws: Either<Transport, Counter.Error>.right(.exceeded)) {
            try await client.counter.increment(limit: .init(value: 10))
        }
    }

    @Test
    func `a derived client surfaces a transport failure on the left`() async {
        let wire = Wire { _ throws(Transport) in throw .unreachable }
        let client = Example.Client.client(routing: router, replying: replies, over: wire)

        await #expect(throws: Either<Transport, Counter.Error>.left(.unreachable)) {
            try await client.counter.increment(limit: .init(value: 1))
        }
        await #expect(throws: Either<Transport, Never>.left(.unreachable)) {
            try await client.greeting.greet(.init(value: "Blob"))
        }
    }

    @Test
    func `a derived client lifts an undecodable reply through the interpretation`() async {
        let wire = Wire { _ throws(Transport) in "garbage" }
        let client = Example.Client.client(routing: router, replying: replies, over: wire)

        await #expect(throws: Either<Transport, Counter.Error>.left(.malformed)) {
            try await client.counter.increment(limit: .init(value: 1))
        }
    }

    @Test
    func `a derived client completes a void operation over an empty reply`() async throws {
        let wire = Wire(respond: serve)
        let client = Example.Client.client(routing: router, replying: replies, over: wire)

        try await client.counter.reset()

        let broken = Wire { _ throws(Transport) in "unexpected" }
        let refusing = Example.Client.client(routing: router, replying: replies, over: broken)
        await #expect(throws: Either<Transport, Never>.left(.malformed)) {
            try await refusing.counter.reset()
        }
    }
}
