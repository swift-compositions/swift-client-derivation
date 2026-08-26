import Algebra_Derivation
import Client
import Testing

public enum GreetingAlgebraFixture {
    @Algebra
    package protocol Signature {
        func greet(_ name: String) async -> String
    }
}

@Test
func algebraDerivesInfallibleClientArrow() async {
    let client = GreetingAlgebraFixture.Client(
        greet: { "Hello, \($0)" }
    )
    #expect(await client.greet("Ada") == "Hello, Ada")
}
