//
//  HUDView.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import SwiftUI

struct HUDView: View {
    @ObservedObject var audioManager: AudioInputManager
    @ObservedObject var speechService: TranscriptionService
    
    @State private var conversation: [DialogueLine] = []
    
    var body: some View {
        VStack {
            Text("blubble")
                .font(.headline)
                .padding(.top)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(conversation) { line in
                            Text(line.text)
                                .padding(10)
                                // User text on right (blue), Partner on left (gray)
                                .background(line.speaker == .user ? Color.blue.opacity(0.7) : Color.gray.opacity(0.7))
                                .cornerRadius(10)
                                .frame(maxWidth: .infinity, alignment: line.speaker == .user ? .trailing : .leading)
                        }
                    }
                }
                .onChange(of: speechService.transcript) { oldTranscript, newTranscript in
                    if speechService.isFinal {
                        // [cite: 15, 27] Logic to separate user/partner based on audio heuristics
                        let newSpeaker: SpeakerType = audioManager.currentRMS > 0.05 ? .user : .partner
                        let newLine = DialogueLine(text: newTranscript, speaker: newSpeaker)
                        conversation.append(newLine)
                        
                        // Reset the service for the next sentence
                        speechService.transcript = ""
                    }
                }
            }
        }
        .frame(width: 500, height: 300)
        .background(.ultraThinMaterial) // Requirement: Translucent HUD [cite: 13]
        .cornerRadius(20)
    }
}
