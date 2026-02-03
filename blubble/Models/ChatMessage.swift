//
//  ChatMessage.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let speaker: Int
    let timestamp: Date
}
