public import Client
public import Coder
public import Either
public import Operation
public import Parser
public import Serializer

extension Interpretation {

    public func arrow<
        Index: Operation.Symbol,
        Route: ~Copyable,
        Request: Coder.`Protocol`,
        Response: Coder.`Protocol`
    >(
        _: Index.Type,
        requesting request: Request,
        replying response: Response,
        embedding embed: @escaping (Operation.Application<Index>) -> Route
    ) -> Client::Client<Index.Input, Index.Output, Either<External, Index.Failure>>
    where
        Index.Input: Copyable & Escapable,
        Index.Output: Copyable & Escapable,
        Index.Failure: Swift.Error & Copyable & Escapable,
        Request.Input == Message,
        Request.Output == Route,
        Request.Buffer == Message,
        Request.Failure == Routing,
        Response.Input == Reply,
        Response.Output == Either<Index.Failure, Index.Output>,
        Response.Buffer == Reply,
        Response.Failure == Routing
    {
        let interpretation = self
        return .init(
            run: { input throws(Either<External, Index.Failure>) in
                var message = interpretation.blank
                do throws(Routing) {
                    try request.serialize(embed(.init(input)), into: &message)
                } catch {
                    throw .left(interpretation.external(error))
                }

                var reply: Reply
                do throws(External) {
                    reply = try await interpretation.send(message)
                } catch {
                    throw .left(error)
                }

                let outcome: Either<Index.Failure, Index.Output>
                do throws(Routing) {
                    outcome = try response.parse(&reply)
                } catch {
                    throw .left(interpretation.external(error))
                }

                switch outcome {
                case .left(let refusal):
                    throw .right(refusal)
                case .right(let output):
                    return output
                }
            }
        )
    }
}
