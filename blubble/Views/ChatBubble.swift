//
//  ChatBubble.swift
//  blubble
//
//  Created by Jeffrey Song on 2/14/26.
//

import SwiftUI

struct ChatBubble: View {
    let text: String
    let speaker: Int
    let isPending: Bool
    let emotion: Emotion
    
    @State private var appeared = false
    @State private var shakeTrigger = false
    
    var isUser: Bool {
        return speaker == 0
    }
    
    private var bubbleColor: Color {
        if appeared && emotion == .anger { return Color(red: 0.75, green: 0, blue: 0) }
        return isUser ? .blue : Color(.systemGray5)
    }
    
    private var textColor: Color {
        if appeared && (isUser || emotion == .anger) { return .white }
        return .primary
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer() }
            
            if !isUser { avatarView(label: "\(speaker)", color: .orange) }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text)
                    .padding(12)
                    .background(bubbleColor.opacity(0.9))
                    .foregroundColor(textColor)
                    .cornerRadius(16)
                    .animation(.easeInOut(duration: 0.8), value: appeared)
                    .opacity(isPending ? 0.7 : 1.0)
                
                if isPending {
                    Text("Speaking...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .emotionEffect(emotion)
            
            if isUser { avatarView(label: "0", color: .blue) }
            if !isUser { Spacer() }
        }
        .onAppear {
            appeared = true
        }
    }
    
    @ViewBuilder
    private func avatarView(label: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay(
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
            )
    }
}
