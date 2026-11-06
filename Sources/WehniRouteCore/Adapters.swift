import Foundation

/// Provider-agnostic request/response shape. The gateway converts OpenAI or
/// Anthropic payloads into this, the router picks a candidate, and the
/// provider adapters convert it back out.
public struct CanonicalRequest: Sendable, Equatable {
    public var messages: [JSONValue]
    public var tools: [JSONValue]?
    public var stream: Bool
    public var maxTokens: Int?
    public var temperature: Double?
    public var responseFormat: JSONValue?

    public init(
        messages: [JSONValue],
        tools: [JSONValue]? = nil,
        stream: Bool = false,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        responseFormat: JSONValue? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.stream = stream
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.responseFormat = responseFormat
    }

    public static func fromOpenAI(_ body: JSONValue) -> CanonicalRequest {
        CanonicalRequest(
            messages: body["messages"]?.arrayValue ?? [],
            tools: body["tools"]?.arrayValue,
            stream: body["stream"]?.boolValue ?? false,
            maxTokens: body["max_tokens"]?.intValue ?? body["max_completion_tokens"]?.intValue,
            temperature: body["temperature"]?.doubleValue,
            responseFormat: body["response_format"]
        )
    }

    public static func fromAnthropic(_ body: JSONValue) -> CanonicalRequest {
        var messages: [JSONValue] = []
        if let system = systemText(from: body["system"]), !system.isEmpty {
            messages.append(.object(["role": .string("system"), "content": .string(system)]))
        }

        for message in body["messages"]?.arrayValue ?? [] {
            let role = message["role"]?.stringValue ?? "user"
            switch message["content"] {
            case .string(let text)?:
                messages.append(.object(["role": .string(role), "content": .string(text)]))
            case .array(let blocks)?:
                var textParts: [String] = []
                var toolCalls: [JSONValue] = []
                var toolResults: [JSONValue] = []
                var imageBlocks: [JSONValue] = []

                for block in blocks {
                    switch block["type"]?.stringValue {
                    case "text":
                        if let text = block["text"]?.stringValue { textParts.append(text) }
                    case "image":
                        if let url = imageURL(from: block) {
                            imageBlocks.append(.object([
                                "type": .string("image_url"),
                                "image_url": .object(["url": .string(url)]),
                            ]))
                        }
                    case "tool_use":
                        toolCalls.append(.object([
                            "id": .string(block["id"]?.stringValue ?? "call_\(UUID().uuidString.prefix(8))"),
                            "type": .string("function"),
                            "function": .object([
                                "name": .string(block["name"]?.stringValue ?? ""),
                                "arguments": .string((block["input"] ?? .object([:])).jsonString),
                            ]),
                        ]))
                    case "tool_result":
                        let content = block["content"]
                        toolResults.append(.object([
                            "role": .string("tool"),
                            "tool_call_id": .string(block["tool_use_id"]?.stringValue ?? ""),
                            "content": .string(content?.stringValue ?? content?.jsonString ?? ""),
                        ]))
                    default:
                        break
                    }
                }

                if !toolCalls.isEmpty {
                    messages.append(.object([
                        "role": .string("assistant"),
                        "content": textParts.isEmpty ? .null : .string(textParts.joined()),
                        "tool_calls": .array(toolCalls),
                    ]))
                } else if !imageBlocks.isEmpty {
                    var contentBlocks: [JSONValue] = []
                    if !textParts.isEmpty {
                        contentBlocks.append(.object([
                            "type": .string("text"),
                            "text": .string(textParts.joined()),
                        ]))
                    }
                    contentBlocks.append(contentsOf: imageBlocks)
                    messages.append(.object(["role": .string(role), "content": .array(contentBlocks)]))
                } else if !textParts.isEmpty {
                    messages.append(.object(["role": .string(role), "content": .string(textParts.joined())]))
                }
                messages.append(contentsOf: toolResults)
            default:
                break
            }
        }

        let tools = body["tools"]?.arrayValue?.map { tool -> JSONValue in
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": tool["name"] ?? .string(""),
                    "description": tool["description"] ?? .string(""),
                    "parameters": tool["input_schema"] ?? .object([:])
                ]),
            ])
        }

        return CanonicalRequest(
            messages: messages,
            tools: tools,
            stream: body["stream"]?.boolValue ?? false,
            maxTokens: body["max_tokens"]?.intValue,
            temperature: body["temperature"]?.doubleValue,
            responseFormat: nil
        )
    }

    public func openAIBody(model: String, stream: Bool = false) -> JSONValue {
        var payload: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(messages),
            "stream": .bool(stream),
        ]
        if let tools, !tools.isEmpty { payload["tools"] = .array(tools) }
        if let maxTokens { payload["max_tokens"] = .num(maxTokens) }
        if let temperature { payload["temperature"] = .num(temperature) }
        if let responseFormat { payload["response_format"] = responseFormat }
        return .object(payload)
    }

    public func anthropicBody(model: String) -> JSONValue {
        var payload: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .num(maxTokens ?? 4096),
            "messages": .array(anthropicMessages()),
            "stream": .bool(false),
        ]
        let system = messages
            .compactMap { $0["role"]?.stringValue == "system" ? $0["content"]?.stringValue : nil }
            .joined(separator: "\n")
        if !system.isEmpty { payload["system"] = .string(system) }
        if let temperature { payload["temperature"] = .num(temperature) }
        if let tools, !tools.isEmpty {
            payload["tools"] = .array(tools.map(anthropicTool))
        }
        return .object(payload)
    }

    public func lastUserText() -> String {
        for message in messages.reversed() {
            guard message["role"]?.stringValue == "user" else { continue }
            if let text = message["content"]?.stringValue { return text }
            if let blocks = message["content"]?.arrayValue {
                let text = blocks.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    public func preview(limit: Int = 180) -> String {
        let text = lastUserText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    // MARK: - Anthropic helpers

    private func anthropicMessages() -> [JSONValue] {
        var result: [JSONValue] = []
        for message in messages {
            let role = message["role"]?.stringValue ?? "user"
            if role == "system" { continue }

            if role == "tool" {
                result.append(.object([
                    "role": .string("user"),
                    "content": .array([
                        .object([
                            "type": .string("tool_result"),
                            "tool_use_id": .string(message["tool_call_id"]?.stringValue ?? ""),
                            "content": .string(message["content"]?.stringValue ?? message["content"]?.jsonString ?? ""),
                        ])
                    ]),
                ]))
                continue
            }

            if role == "assistant" {
                let calls = message["tool_calls"]?.arrayValue ?? []
                if !calls.isEmpty {
                    var blocks: [JSONValue] = []
                    if let text = message["content"]?.stringValue, !text.isEmpty {
                        blocks.append(.object(["type": .string("text"), "text": .string(text)]))
                    }
                    for call in calls {
                        let function = call["function"]
                        let arguments = function?["arguments"]?.stringValue ?? "{}"
                        let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(arguments.utf8))) ?? .object([:])
                        blocks.append(.object([
                            "type": .string("tool_use"),
                            "id": .string(call["id"]?.stringValue ?? ""),
                            "name": .string(function?["name"]?.stringValue ?? ""),
                            "input": input,
                        ]))
                    }
                    result.append(.object(["role": .string("assistant"), "content": .array(blocks)]))
                    continue
                }
            }

            result.append(.object([
                "role": .string(role),
                "content": message["content"] ?? .string(""),
            ]))
        }
        return result
    }

    private func anthropicTool(_ tool: JSONValue) -> JSONValue {
        let function = tool["function"]
        return .object([
            "name": function?["name"] ?? .string(""),
            "description": function?["description"] ?? .string(""),
            "input_schema": function?["parameters"] ?? .object([:]),
        ])
    }

    private static func systemText(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.stringValue { return text }
        if let blocks = value.arrayValue {
            return blocks.compactMap { $0["text"]?.stringValue }.joined(separator: "\n")
        }
        return nil
    }

    private static func imageURL(from block: JSONValue) -> String? {
        guard let source = block["source"] else { return nil }
        if let url = source["url"]?.stringValue { return url }
        if let data = source["data"]?.stringValue {
            let media = source["media_type"]?.stringValue ?? "image/png"
            return "data:\(media);base64,\(data)"
        }
        return nil
    }
}

public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct CanonicalResponse: Sendable, Equatable {
    public var id: String
    public var model: String
    public var text: String
    public var toolCalls: [ToolCall]
    public var finishReason: String
    public var usage: TokenUsage

    public init(
        id: String,
        model: String,
        text: String,
        toolCalls: [ToolCall],
        finishReason: String,
        usage: TokenUsage
    ) {
        self.id = id
        self.model = model
        self.text = text
        self.toolCalls = toolCalls
        self.finishReason = finishReason
        self.usage = usage
    }

    public var stopReasonAnthropic: String {
        switch finishReason {
        case "tool_calls": return "tool_use"
        case "length": return "max_tokens"
        default: return "end_turn"
        }
    }

    public func openAIBody() -> JSONValue {
        var message: [String: JSONValue] = ["role": .string("assistant")]
        if text.isEmpty && !toolCalls.isEmpty {
            message["content"] = .null
        } else {
            message["content"] = .string(text)
        }
        if !toolCalls.isEmpty {
            message["tool_calls"] = .array(toolCalls.map { call in
                .object([
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(call.arguments),
                    ]),
                ])
            })
        }

        return .object([
            "id": .string(id),
            "object": .string("chat.completion"),
            "created": .num(Int(Date().timeIntervalSince1970)),
            "model": .string(model),
            "choices": .array([
                .object([
                    "index": .num(0),
                    "message": .object(message),
                    "finish_reason": .string(finishReason),
                ])
            ]),
            "usage": .object([
                "prompt_tokens": .num(usage.input),
                "completion_tokens": .num(usage.output),
                "total_tokens": .num(usage.total),
            ]),
        ])
    }

    public func anthropicBody() -> JSONValue {
        var blocks: [JSONValue] = []
        if !text.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string(text)]))
        }
        for call in toolCalls {
            let input = (try? JSONDecoder().decode(JSONValue.self, from: Data(call.arguments.utf8))) ?? .object([:])
            blocks.append(.object([
                "type": .string("tool_use"),
                "id": .string(call.id),
                "name": .string(call.name),
                "input": input,
            ]))
        }
        if blocks.isEmpty {
            blocks.append(.object(["type": .string("text"), "text": .string("")]))
        }

        return .object([
            "id": .string(id),
            "type": .string("message"),
            "role": .string("assistant"),
            "model": .string(model),
            "content": .array(blocks),
            "stop_reason": .string(stopReasonAnthropic),
            "stop_sequence": .null,
            "usage": .object([
                "input_tokens": .num(usage.input),
                "output_tokens": .num(usage.output),
            ]),
        ])
    }

    public func openAIStreamFrames() -> [Data] {
        var delta: [String: JSONValue] = ["role": .string("assistant")]
        if !text.isEmpty { delta["content"] = .string(text) }
        if !toolCalls.isEmpty {
            delta["tool_calls"] = .array(toolCalls.enumerated().map { index, call in
                .object([
                    "index": .num(index),
                    "id": .string(call.id),
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(call.name),
                        "arguments": .string(call.arguments),
                    ]),
                ])
            })
        }

        let created = JSONValue.num(Int(Date().timeIntervalSince1970))
        let chunk: [String: JSONValue] = [
            "id": .string(id),
            "object": .string("chat.completion.chunk"),
            "created": created,
            "model": .string(model),
            "choices": .array([
                .object([
                    "index": .num(0),
                    "delta": .object(delta),
                    "finish_reason": .null,
                ])
            ]),
        ]
        let finish: [String: JSONValue] = [
            "id": .string(id),
            "object": .string("chat.completion.chunk"),
            "created": created,
            "model": .string(model),
            "choices": .array([
                .object([
                    "index": .num(0),
                    "delta": .object([:]),
                    "finish_reason": .string(finishReason),
                ])
            ]),
        ]
        return [SSE.frame(.object(chunk)), SSE.frame(.object(finish)), SSE.done]
    }

    public func anthropicStreamFrames() -> [Data] {
        var frames: [Data] = []
        frames.append(SSE.frame(event: "message_start", .object([
            "type": .string("message_start"),
            "message": .object([
                "id": .string(id),
                "type": .string("message"),
                "role": .string("assistant"),
                "model": .string(model),
                "content": .array([]),
                "stop_reason": .null,
                "stop_sequence": .null,
                "usage": .object([
                    "input_tokens": .num(usage.input),
                    "output_tokens": .num(0),
                ]),
            ]),
        ])))

        var index = 0
        if !text.isEmpty {
            frames.append(SSE.frame(event: "content_block_start", .object([
                "type": .string("content_block_start"),
                "index": .num(index),
                "content_block": .object(["type": .string("text"), "text": .string("")]),
            ])))
            frames.append(SSE.frame(event: "content_block_delta", .object([
                "type": .string("content_block_delta"),
                "index": .num(index),
                "delta": .object(["type": .string("text_delta"), "text": .string(text)]),
            ])))
            frames.append(SSE.frame(event: "content_block_stop", .object([
                "type": .string("content_block_stop"),
                "index": .num(index),
            ])))
            index += 1
        }

        for call in toolCalls {
            frames.append(SSE.frame(event: "content_block_start", .object([
                "type": .string("content_block_start"),
                "index": .num(index),
                "content_block": .object([
                    "type": .string("tool_use"),
                    "id": .string(call.id),
                    "name": .string(call.name),
                    "input": .object([:]),
                ]),
            ])))
            frames.append(SSE.frame(event: "content_block_delta", .object([
                "type": .string("content_block_delta"),
                "index": .num(index),
                "delta": .object([
                    "type": .string("input_json_delta"),
                    "partial_json": .string(call.arguments),
                ]),
            ])))
            frames.append(SSE.frame(event: "content_block_stop", .object([
                "type": .string("content_block_stop"),
                "index": .num(index),
            ])))
            index += 1
        }

        frames.append(SSE.frame(event: "message_delta", .object([
            "type": .string("message_delta"),
            "delta": .object([
                "stop_reason": .string(stopReasonAnthropic),
                "stop_sequence": .null,
            ]),
            "usage": .object(["output_tokens": .num(usage.output)]),
        ])))
        frames.append(SSE.frame(event: "message_stop", .object(["type": .string("message_stop")])))
        return frames
    }
}

public enum OpenAIAdapter {
    public static func parse(_ body: JSONValue) -> CanonicalResponse {
        let choice = body["choices"]?.arrayValue?.first
        let message = choice?["message"]
        let text = message?["content"]?.stringValue
            ?? message?["content"]?.arrayValue?.compactMap { $0["text"]?.stringValue }.joined()
            ?? ""
        let calls = (message?["tool_calls"]?.arrayValue ?? []).map { call in
            ToolCall(
                id: call["id"]?.stringValue ?? "call_\(UUID().uuidString.prefix(8))",
                name: call["function"]?["name"]?.stringValue ?? "",
                arguments: call["function"]?["arguments"]?.stringValue ?? "{}"
            )
        }
        let usage = body["usage"]
        return CanonicalResponse(
            id: body["id"]?.stringValue ?? "chatcmpl_\(UUID().uuidString.prefix(8))",
            model: body["model"]?.stringValue ?? "auto",
            text: text,
            toolCalls: calls,
            finishReason: choice?["finish_reason"]?.stringValue ?? (calls.isEmpty ? "stop" : "tool_calls"),
            usage: TokenUsage(
                input: usage?["prompt_tokens"]?.intValue ?? 0,
                output: usage?["completion_tokens"]?.intValue ?? 0
            )
        )
    }
}

public enum AnthropicAdapter {
    public static func parse(_ body: JSONValue) -> CanonicalResponse {
        let blocks = body["content"]?.arrayValue ?? []
        let text = blocks
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
        let calls = blocks
            .filter { $0["type"]?.stringValue == "tool_use" }
            .map { block in
                ToolCall(
                    id: block["id"]?.stringValue ?? "toolu_\(UUID().uuidString.prefix(8))",
                    name: block["name"]?.stringValue ?? "",
                    arguments: (block["input"] ?? .object([:])).jsonString
                )
            }

        let stop = body["stop_reason"]?.stringValue
        let finish: String
        switch stop {
        case "tool_use": finish = "tool_calls"
        case "max_tokens": finish = "length"
        default: finish = "stop"
        }

        let usage = body["usage"]
        return CanonicalResponse(
            id: body["id"]?.stringValue ?? "msg_\(UUID().uuidString.prefix(8))",
            model: body["model"]?.stringValue ?? "auto",
            text: text,
            toolCalls: calls,
            finishReason: finish,
            usage: TokenUsage(
                input: usage?["input_tokens"]?.intValue ?? 0,
                output: usage?["output_tokens"]?.intValue ?? 0
            )
        )
    }
}

public enum SSE {
    public static func frame(event: String? = nil, _ value: JSONValue) -> Data {
        var text = ""
        if let event { text += "event: \(event)\n" }
        text += "data: \(value.jsonString)\n\n"
        return Data(text.utf8)
    }

    public static let done = Data("data: [DONE]\n\n".utf8)
}
