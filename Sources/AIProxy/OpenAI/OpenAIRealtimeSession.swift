//
//  RealtimeSession.swift
//
//
//  Created by Lou Zell on 11/28/24.
//

import Foundation
import AVFoundation

@RealtimeActor
open class OpenAIRealtimeSession {
    private var isTearingDown = false
    private let webSocketTask: URLSessionWebSocketTask
    private var continuation: AsyncStream<OpenAIRealtimeMessage>.Continuation?
    let sessionConfiguration: OpenAIRealtimeSessionConfiguration

    init(
        webSocketTask: URLSessionWebSocketTask,
        sessionConfiguration: OpenAIRealtimeSessionConfiguration
    ) {
        self.webSocketTask = webSocketTask
        self.sessionConfiguration = sessionConfiguration

        Task {
            await self.sendMessage(OpenAIRealtimeSessionUpdate(session: self.sessionConfiguration))
        }
        self.webSocketTask.resume()
        self.receiveMessage()
    }

    deinit {
        logIf(.debug)?.debug("OpenAIRealtimeSession is being freed")
    }

    /// Messages sent from OpenAI are published on this receiver as they arrive
    public var receiver: AsyncStream<OpenAIRealtimeMessage> {
        return AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Sends a message through the websocket connection
    public func sendMessage(_ encodable: Encodable) async {
        guard !self.isTearingDown else {
            logIf(.debug)?.debug("Ignoring ws sendMessage. The RT session is tearing down.")
            return
        }
        do {
            let wsMessage = URLSessionWebSocketTask.Message.string(try encodable.serialize())
            try await self.webSocketTask.send(wsMessage)
        } catch {
            logIf(.error)?.error("Could not send message to OpenAI: \(error.localizedDescription)")
        }
    }

    /// Close the websocket connection
    public func disconnect() {
        logIf(.debug)?.debug("Disconnecting from realtime session")
        self.isTearingDown = true
        self.continuation?.finish()
        self.continuation = nil
        self.webSocketTask.cancel()
    }

    /// Tells the websocket task to receive a new message
    private func receiveMessage() {
        self.webSocketTask.receive { result in
            switch result {
            case .failure(let error as NSError):
                Task {
                    await self.didReceiveWebSocketError(error)
                }
            case .success(let message):
                Task {
                    await self.didReceiveWebSocketMessage(message)
                }
            }
        }
    }

    /// Handles socket errors. We disconnect on all errors.
    private func didReceiveWebSocketError(_ error: NSError) {
        guard !isTearingDown else {
            return
        }
        if error.code == 57 {
            logIf(.warning)?.warning("WS disconnected. Check that your AIProxy project is websocket enabled and you've followed the DeviceCheck integration guide")
        } else {
            logIf(.error)?.error("Received ws error: \(error.localizedDescription)")
        }
        self.disconnect()
    }

    /// Handles received websocket messages
    private func didReceiveWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8) {
                self.didReceiveWebSocketData(data)
            }
        case .data(let data):
            self.didReceiveWebSocketData(data)
        @unknown default:
            logIf(.error)?.error("Received an unknown websocket message format")
            self.disconnect()
        }
    }

    private func didReceiveWebSocketData(_ data: Data) {
        guard !self.isTearingDown else {
            // The caller already initiated disconnect,
            // don't send any more messages back to the caller
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = json["type"] as? String else {
            logIf(.error)?.error("Received websocket data that we don't understand")
            self.disconnect()
            return
        }
        logIf(.debug)?.debug("Received \(messageType) from OpenAI")

        switch messageType {
        case "error":
            let errorBody = String(describing: json["error"] as? [String: Any])
            self.continuation?.yield(.error(errorBody))
            
        // Session events
        case "session.created":
            self.continuation?.yield(.sessionCreated)
        case "session.updated":
            self.continuation?.yield(.sessionUpdated)
            
        // Response events    
        case "response.created":
            self.continuation?.yield(.responseCreated)
        case "response.text.delta":
            if let textDelta = json["delta"] as? String {
                self.continuation?.yield(.responseTextDelta(textDelta))
            }
        case "response.text.done":
            self.continuation?.yield(.responseTextDone)
        case "response.audio_transcript.done":
            if let transcriptString = json["transcript"] as? String {
                self.continuation?.yield(.responseAudio_transcriptDone(transcriptString))
            }
        case "response.audio_transcript.delta":
            if let textDelta = json["delta"] as? String {
                self.continuation?.yield(.responseAudio_transcriptDelta(textDelta))
            }
        
        case "response.audio.delta":
            if let base64Audio = json["delta"] as? String {
                self.continuation?.yield(.responseAudioDelta(base64Audio))
            }
        case "response.audio.done":
            self.continuation?.yield(.responseAudioDone)
        // case "response.audio_transcript.done":
        //     self.continuation?.yield(.responseAudioDone)
        case "response.function_call":
            if let functionCall = json["function_call"] as? [String: Any] {
                let name = functionCall["name"] as? String
                let args = functionCall["arguments"] as? String
                self.continuation?.yield(.responseFunctionCall(OpenAIFunctionCall(name: name, arguments: args)))
            }
        case "response.tool_calls":
            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                let parsedCalls = toolCalls.map { dict -> OpenAIToolCall in
                    let id = dict["id"] as? String
                    let type = dict["type"] as? String
                    let function = (dict["function"] as? [String: Any]).map { f -> OpenAIFunctionCall in
                        OpenAIFunctionCall(
                            name: f["name"] as? String,
                            arguments: f["arguments"] as? String
                        )
                    }
                    return OpenAIToolCall(id: id, type: type, function: function)
                }
                self.continuation?.yield(.responseToolCalls(parsedCalls))
            }
            
        // Input events    
        case "input_audio_buffer.speech_started":
            self.continuation?.yield(.inputAudioBufferSpeechStarted)
        case "input_audio_buffer.delta":
            if let delta = json["delta"] as? String {
                self.continuation?.yield(.inputAudioBufferDelta(delta))
            }
        case "input_audio_buffer.done":
            self.continuation?.yield(.inputAudioBufferDone)
        case "input_text.delta":
            if let delta = json["delta"] as? String {
                self.continuation?.yield(.inputTextDelta(delta))
            }
        case "input_text.done":
            self.continuation?.yield(.inputTextDone)
            
        // Conversation events    
        case "conversation.created":
            self.continuation?.yield(.conversationCreated)
        case "conversation.updated":
            self.continuation?.yield(.conversationUpdated)
        case "conversation.done":
            self.continuation?.yield(.conversationDone)
        case "conversation.item.created":
            self.continuation?.yield(.conversationItemCreated)
        case "conversation.item.updated":
            self.continuation?.yield(.conversationItemUpdated)
        case "conversation.item.input":
            self.continuation?.yield(.conversationItemInput)
        case "conversation.item.response":
            self.continuation?.yield(.conversationItemResponse)
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                print(delta)
                self.continuation?.yield(.conversationIitemInput_audio_transcriptionDelta(delta))
            }
            
        // Turn events    
        case "turn.created":
            self.continuation?.yield(.turnCreated)
        case "turn.updated":
            self.continuation?.yield(.turnUpdated)
        case "turn.done":
            self.continuation?.yield(.turnDone)
            
        default:
            logIf(.debug)?.debug("Unhandled message type: \(messageType)")
        }
        
        // Continue receiving if not an error
        if messageType != "error" && !self.isTearingDown {
            self.receiveMessage()
        }
    }
}
