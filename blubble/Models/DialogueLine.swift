//
//  DialogueLine.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation

struct DialogueLine: Identifiable {
    let id = UUID()
    let text: String
    let speaker: SpeakerType
    let timestamp: Date = Date()
}

enum SpeakerType {
    case user
    case partner
}
