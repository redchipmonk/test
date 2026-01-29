//
//  ImmersiveView.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import SwiftUI
import RealityKit

struct ImmersiveView: View {
    // 1. Initialize our logic managers as StateObjects
    @StateObject var audioManager = AudioInputManager()
    @StateObject var transcriptionService = TranscriptionService()

    var body: some View {
        RealityView { content, attachments in
            // 1. Create a head-anchored entity
            let headAnchor = AnchorEntity(.head)
            
            if let hud = attachments.entity(for: "HUD_Attachment") {
                // 2. Position it: 0.2m up (above eye level) and 0.5m away
                // This keeps it in your peripheral vision as required by your PRD
                hud.position = [0, 0.2, -0.5]
                
                // 3. Add the HUD to the head anchor
                headAnchor.addChild(hud)
            }
            
            // 4. Add the anchor to the scene
            content.add(headAnchor)
            
            audioManager.startMonitoring()
        } update: { content, attachments in
            // This runs every frame; we can use it to pass audio data
            // to the transcription service if needed.
        } attachments: {
            // 4. Define the SwiftUI attachment
            Attachment(id: "HUD_Attachment") {
                HUDView(audioManager: audioManager, speechService: transcriptionService)
            }
        }
    }
}

