import Testing
@testable import SSCore

@Test func schemaVersionIsStable() {
    #expect(SchemaVersion.current == 1)
}
