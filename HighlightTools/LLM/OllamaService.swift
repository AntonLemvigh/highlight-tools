import Foundation

/// LLM service that connects to a local Ollama instance.
/// Streams responses via Ollama's NDJSON format.
class OllamaService: LLMService {

    private let baseURL: String
    private let model: String

    init(baseURL: String = SettingsManager.shared.ollamaBaseURL,
         model: String = SettingsManager.shared.ollamaModel) {
        self.baseURL = baseURL
        self.model = model
    }

    // MARK: - Availability Check

    var isAvailable: Bool {
        get async {
            guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
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
                    guard let url = URL(string: "\(baseURL)/api/generate") else {
                        continuation.finish(throwing: LLMError.connectionFailed("Invalid Ollama URL: \(baseURL)"))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "model": model,
                        "system": systemPrompt,
                        "prompt": userContent,
                        "stream": true,
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        continuation.finish(throwing: LLMError.connectionFailed("HTTP \(httpResponse.statusCode)"))
                        return
                    }

                    // Parse NDJSON: each line is a JSON object with a "response" field
                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }

                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(OllamaChunk.self, from: data) else {
                            continue
                        }

                        if !chunk.response.isEmpty {
                            continuation.yield(chunk.response)
                        }

                        if chunk.done {
                            break
                        }
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

/// A single chunk in Ollama's NDJSON streaming response.
private struct OllamaChunk: Decodable {
    let response: String
    let done: Bool
}
