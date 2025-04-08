//
//  OpenAIRealtimeMessage.swift
//  AIProxy
//
//  Created by Lou Zell on 12/29/24.
//

public enum OpenAIRealtimeMessage {
    // Session events
    case error(String?)
    case sessionCreated              // "session.created"
    case sessionUpdated              // "session.updated"
    
    // Response events
    case responseCreated             // "response.created" 
    case responseTextDelta(String)   // "response.text.delta"
    case responseTextDone            // "response.text.done"
    case responseAudioDone            // "response.audio.done"
    case responseAudio_transcriptDone(String)            // "response.audio_transcript.done"
    case responseAudioDelta(String)  // "response.audio.delta"
    case responseAudio_transcriptDelta(String) // "response.audio.done"
    case responseFunctionCall(OpenAIFunctionCall)  // "response.function_call"
    case responseToolCalls([OpenAIToolCall])       // "response.tool_calls"
    
    // Input events
    case inputAudioBufferSpeechStarted  // "input_audio_buffer.speech_started"
    case inputAudioBufferDelta(String)  // "input_audio_buffer.delta" 
    case inputAudioBufferDone           // "input_audio_buffer.done"
    case inputTextDelta(String)         // "input_text.delta"
    case inputTextDone                  // "input_text.done"
    
    // Conversation events 
    case conversationIitemInput_audio_transcriptionDelta(String) // "conversation.item.input.audio.transcription.delta"
    case conversationItemCreated        // "conversation.item.created"
    case conversationItemUpdated        // "conversation.item.updated"
    case conversationItemInput         // "conversation.item.input"
    case conversationItemResponse      // "conversation.item.response"
    case conversationCreated           // "conversation.created"
    case conversationUpdated           // "conversation.updated"
    case conversationDone              // "conversation.done"
    
    // Turn events
    case turnCreated    // "turn.created"
    case turnUpdated    // "turn.updated" 
    case turnDone       // "turn.done"

    // Debug
    case debug(String)  // "debug"
}

public struct OpenAIFunctionCall {
    public let name: String?
    public let arguments: String?
}

public struct OpenAIToolCall {
    public let id: String?
    public let type: String?
    public let function: OpenAIFunctionCall?
}
