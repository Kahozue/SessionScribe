import Foundation
import Testing
@testable import SSCore

struct CloudLLMErrorTests {
    @Test func http錯誤訊息包含供應商回傳原因() {
        let body = #"{"error":{"message":"The model `whisper-1` is not available."}}"#
        let message = CloudLLMError.http(status: 400, body: body).userMessage

        #expect(message.contains("雲端服務回應錯誤（400）"))
        #expect(message.contains("The model `whisper-1` is not available."))
    }
}
