import Foundation

struct DeepgramResponse: Codable {
    let type: String?
    let channel: DeepgramChannel?
    let metadata: DeepgramMetadata?
    let is_final: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type, channel, metadata
        case is_final
    }
}

struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]
}

struct DeepgramAlternative: Codable {
    let transcript: String
    let confidence: Double
    let words: [DeepgramWord]
}

struct DeepgramWord: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
    let speaker: Int?
    let speakerConfidence: Double?
    
    enum CodingKeys: String, CodingKey {
        case word, start, end, confidence, speaker
        case speakerConfidence = "speaker_confidence"
    }
}

struct DeepgramMetadata: Codable {
    let requestId: String?
    let created: String?
    let duration: Double?
    let channels: Int?
    
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case created, duration, channels
    }
}
