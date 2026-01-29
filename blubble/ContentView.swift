//
//  ContentView.swift
//  blubble
//
//  Created by Alvin Ngoc Le on 1/28/26.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @StateObject private var audioManager: AudioInputManager
    @StateObject private var transcriptionService = TranscriptionService()

    init() {
        let service = TranscriptionService()
        _transcriptionService = StateObject(wrappedValue: service)
        _audioManager = StateObject(wrappedValue: AudioInputManager(transcriptionService: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Model3D(named: "Scene", bundle: realityKitContentBundle)
                .padding(.bottom, 16)

            Text("Live Transcription")
                .font(.title2)
                .bold()

            HStack(spacing: 8) {
                Circle()
                    .fill(audioManager.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(audioManager.isRunning ? "Listening…" : "Idle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    transcriptionService.reset()
                    audioManager.startMonitoring()
                } label: {
                    Label("Start", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    audioManager.stopMonitoring()
                    transcriptionService.reset()
                } label: {
                    Label("Stop", systemImage: "mic.slash.fill")
                }
                .buttonStyle(.bordered)
            }

            // Transcript display
            ScrollView {
                let displayText = transcriptionService.transcript.isEmpty ? "Waiting for speech…" : transcriptionService.transcript
                Text(displayText)
                    .font(.body)
                    .italic(!transcriptionService.isFinal && !transcriptionService.transcript.isEmpty)
                    .foregroundStyle((!transcriptionService.isFinal && !transcriptionService.transcript.isEmpty) ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxHeight: 240)

            Spacer(minLength: 12)

            //ToggleImmersiveSpaceButton()
        }
        .padding()
        .onAppear {
            transcriptionService.reset()
            audioManager.startMonitoring()
        }
    }
}

