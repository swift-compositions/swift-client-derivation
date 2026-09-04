public protocol Interpretation<External> {

    associatedtype External: Swift.Error

    associatedtype Routing: Swift.Error

    associatedtype Message

    associatedtype Reply

    var blank: Message { get }

    func external(_ failure: Routing) -> External

    func send(_ message: Message) async throws(External) -> Reply
}
