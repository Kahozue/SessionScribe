import Testing
@testable import SSCore

struct KeychainStoreTests {
    @Test func 存取與刪除() throws {
        let store = InMemoryKeychainStore()
        try store.setSecret("sk-1", account: "openai")
        #expect(try store.secret(account: "openai") == "sk-1")
        try store.setSecret("sk-2", account: "openai")    // 覆寫
        #expect(try store.secret(account: "openai") == "sk-2")
        try store.deleteSecret(account: "openai")
        #expect(try store.secret(account: "openai") == nil)
    }

    @Test func 未設定回傳nil() throws {
        #expect(try InMemoryKeychainStore().secret(account: "none") == nil)
    }
}
