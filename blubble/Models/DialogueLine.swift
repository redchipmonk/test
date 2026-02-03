//
//  DialogueLine.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation
import simd

struct DialogueLine: Identifiable {
    let id = UUID()
    let text: String
    let speaker: SpeakerType
    let timestamp: Date = Date()
    var worldPosition: SIMD3<Float>? // For partner's spatial position
}

enum SpeakerType {
    case user
    case partner
}
