import Foundation

/// LLM service that connects to any OpenAI-compatible API endpoint.
/// Streams responses via Server-Sent Events (SSE).
class OpenAIService: LLMService {

    private let baseURL: String
    private let apiKey: String
    private let model: String

    init(baseURL: String = SettingsManager.shared.openaiBaseURL,
         apiKey: String = SettingsManager.shared.openaiAPIKey,
         model: String = SettingsManager.shared.openaiModel) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }

    // MARK: - Availability Check

    var isAvailable: Bool {
        get async {
            guard let url = URL(string: "\(baseURL)/v1/models") else { return false }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                return (response as? HTTPURLResponse)?.statusCode == 200
            } catch {
                return false
            }
        }
    }

    // MARK: - Streaming

    func stream(systemPrompt: String, userContent: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
                        continuation.finish(throwing: LLMError.connectionFailed("Invalid API URL: \(baseURL)"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": userContent],
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 200: break
                        case 401:
                            continuation.finish(throwing: LLMError.authenticationFailed)
                            return
                        case 404:
                            continuation.finish(throwing: LLMError.modelNotFound(model))
                            return
                        default:
                            continuation.finish(throwing: LLMError.connectionFailed("HTTP \(httpResponse.statusCode)"))
                            return
                        }
                    }

                    // Parse SSE: lines starting with "data: " contain JSON chunks
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }

                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))

                        if payload == "[DONE]" {
                            break
                        }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OpenAIChatChunk.self, from: data),
                              let content = chunk.choices.first?.delta.content else {
                            continue
                        }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: LLMError.connectionFailed(error.localizedDescription))
                    } else {
                        continuation.finish()
                    }
                }
            }
        }
    }
}

// MARK: - OpenAI Response Types

private struct OpenAIChatChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
