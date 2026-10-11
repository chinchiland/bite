import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Estimates a meal's nutrition from a photo with Claude, through the Messages API.
/// Swift has no official Anthropic SDK, so this is the documented raw HTTP request.
/// Each photo costs about two cents at Claude Opus 5.5 prices ($4 in, $20 out per million tokens).
struct ClaudeVision {
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum Failure: LocalizedError, Equatable {
        case missingKey
        case badKey
        case declined
        case unreadable
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: tr("Add your Claude API key in Settings to estimate photos.")
            case .badKey: tr("Claude didn't accept the API key. Check it in Settings.")
            case .declined: tr("Claude couldn't estimate this photo.")
            case .unreadable: tr("Claude's answer came back unreadable. Try again.")
            case .server(let status): tr("Claude is unavailable right now (%@). Try again soon.", String(status))
            }
        }
    }

    var apiKey: String
    var session: URLSession = .shared

    /// Sends the photo and returns the estimate. The photo should already be a small JPEG.
    /// `isLabel` says the photo is a nutrition label or a pack rather than a plate.
    func estimate(jpeg: Data, language: String, isLabel: Bool = false) async throws -> MealEstimate {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        let request = try Self.request(jpeg: jpeg, language: language, apiKey: apiKey, isLabel: isLabel)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return try Self.parse(data)
        case 401, 403: throw Failure.badKey
        default: throw Failure.server(status)
        }
    }

    static func request(jpeg: Data, language: String, apiKey: String, isLabel: Bool = false) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // If the main model declines, the API retries on Anthropic's recommended fallback model.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body(jpeg: jpeg, language: language, isLabel: isLabel))
        return request
    }

    static func body(jpeg: Data, language: String, isLabel: Bool = false) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "output_config": [
                // Medium keeps the answer quick enough to wait for at the table.
                "effort": "medium",
                "format": ["type": "json_schema", "schema": MealEstimate.schema],
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": jpeg.base64EncodedString(),
                            ],
                        ],
                        ["type": "text", "text": prompt(language: language, isLabel: isLabel)],
                    ],
                ],
            ],
        ]
    }

    static func prompt(language: String, isLabel: Bool = false) -> String {
        let task = isLabel
            ? "This photo shows a nutrition label or a food package. Read it for a calorie tracker: one item for one serving as the label states it, or 100 g when it gives no serving."
            : "This photo is for a calorie tracker. Estimate what one person is eating."
        return """
        \(task)

        List each food or drink you can see as its own item, with the grams on the plate and the \
        kcal, protein, carbs and fat in grams for that amount. Count cooking oil, butter, sauces and \
        dressings you can see or that the dish normally contains. If the photo shows a nutrition \
        label or a packaged product, use what it says.

        Give the meal a short title and one fitting food emoji. Set confidence to low when portions \
        are hidden or hard to judge. Use the note for the one thing most likely to change the \
        number, in one short sentence, or leave it empty.

        If there is no food in the photo, return no items and say so in the note.

        Write the title, item names and note in this language: \(language).
        """
    }

    /// Reads the Messages API response: the JSON lives in the first text block.
    static func parse(_ data: Data) throws -> MealEstimate {
        struct Response: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stop_reason: String?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Failure.unreadable
        }
        if response.stop_reason == "refusal" { throw Failure.declined }
        guard let text = response.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              var estimate = try? JSONDecoder().decode(MealEstimate.self, from: json) else {
            throw Failure.unreadable
        }
        // Drop anything that cannot be a real amount before it reaches the log.
        estimate.items = estimate.items.filter { item in
            [item.grams, item.kcal, item.protein, item.carbs, item.fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 < 20_000 }
        }
        return estimate
    }
}
