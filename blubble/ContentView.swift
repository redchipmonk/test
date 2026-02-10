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
    @StateObject private var identityManager = VoiceIdentityManager()
    @StateObject private var audioManager: AudioInputManager
    @Environment(ConversationStore.self) private var conversationStore
    
    @State private var selectedTab: Tab = .setup // Default to setup? Or transcribe but show calibration needed?
    @State private var showingSaveConfirmation = false

    enum Tab {
        case transcribe
        case history
        case setup
    }
    
    init() {
        let identity = VoiceIdentityManager()
        _identityManager = StateObject(wrappedValue: identity)
        _audioManager = StateObject(wrappedValue: AudioInputManager(apiKey: "9ef63010c60b46f5d8fa0a550b9f418509edb84e", identityManager: identity))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Setup Tab (Calibration)
            CalibrationView(identityManager: identityManager)
                .tabItem {
                    Label("Setup", systemImage: "gearshape")
                }
                .tag(Tab.setup)
            
            // MARK: - Transcribe Tab
            transcribeView
                .tabItem {
                    Label("Transcribe", systemImage: "mic.fill")
                }
                .tag(Tab.transcribe)
            
            // MARK: - History Tab
            SavedConversationsView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(Tab.history)
        }
        .background(.clear)
        .task {
            // Start loading models immediately
            await identityManager.initialize()
        }
    }
    
    // MARK: - Transcribe View
    
    private var transcribeView: some View {
        VStack(spacing: 0) {
            // Header with status and action buttons
            HStack {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(audioManager.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(audioManager.isRunning ? "Transcribing..." : "Ready")
                        .font(.headline)
                        .foregroundStyle(audioManager.isRunning ? .primary : .secondary)
                }
                
                Spacer()
                
                // Action buttons (shown when not recording and has messages)
                if !audioManager.isRunning && !audioManager.chatHistory.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            saveConversation()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive) {
                            clearConversation()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial.opacity(0.5))
            
            // Chat Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(audioManager.chatHistory) { message in
                            ChatBubble(text: message.text, speaker: message.speaker, isPending: false)
                                .id(message.id)
                        }
                        
                        // Pending message
                        if !audioManager.transcript.isEmpty {
                            ChatBubble(
                                text: audioManager.transcript,
                                speaker: audioManager.currentSpeaker ?? 0,
                                isPending: true
                            )
                            .id("pending")
                        }
                    }
                    .padding()
                }
                .onChange(of: audioManager.chatHistory) { _ in
                    if let lastId = audioManager.chatHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: audioManager.transcript) { _ in
                    withAnimation {
                        proxy.scrollTo("pending", anchor: .bottom)
                    }
                }
            }
            
            Spacer()
            
            // Large Start/Stop Button
            if identityManager.calibrationState == .calibrated {
                Button(action: {
                    if audioManager.isRunning {
                        audioManager.stopMonitoring()
                    } else {
                        audioManager.startMonitoring()
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: audioManager.isRunning ? "stop.fill" : "mic.fill")
                            .font(.title2)
                        Text(audioManager.isRunning ? "Stop Transcribing" : "Start Transcribing")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(audioManager.isRunning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .padding()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Calibration Required")
                        .font(.headline)
                    Text("Please go to the Setup tab to calibrate voices before transcribing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Go to Setup") {
                        selectedTab = .setup
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding()
            }
        }
        .background(.clear)
        .alert("Conversation Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your conversation has been saved to History.")
        }
    }
    
    // MARK: - Actions
    
    private func saveConversation() {
        conversationStore.save(audioManager.chatHistory)
        showingSaveConfirmation = true
    }
    
    private func clearConversation() {
        audioManager.chatHistory.removeAll()
        audioManager.transcript = ""
    }
}

// MARK: - Calibration View
struct CalibrationView: View {
    @ObservedObject var identityManager: VoiceIdentityManager
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Instructions")) {
                    Text("To identify speakers correctly, blubble needs to learn your voice and your partner's voice.")
                        .font(.body)
                        .listRowBackground(Color.clear)
                }
                
                Section(header: Text("Step 1: User Voice")) {
                    if identityManager.calibrationState == .userSaved || identityManager.calibrationState == .calibrated || identityManager.calibrationState == .partnerSaved {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("User Voice Configured")
                        }
                    } else {
                        Button(action: {
                            if identityManager.isRecordingEnrollment {
                                identityManager.cancelCalibration() // Stop
                            } else {
                                identityManager.startCalibratingUser()
                            }
                        }) {
                            HStack {
                                Image(systemName: identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForUser ? "stop.circle.fill" : "mic.fill")
                                    .foregroundColor(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForUser ? .red : .blue)
                                VStack(alignment: .leading) {
                                    Text(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForUser ? "Stop & Save (Recording...)" : "Record User Voice (5s)")
                                        .foregroundColor(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForUser ? .red : .primary)
                                    if identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForUser {
                                        Text("Speak naturally...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Step 2: Partner Voice")) {
                    if identityManager.calibrationState == .partnerSaved || identityManager.calibrationState == .calibrated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Partner Voice Configured")
                        }
                    } else {
                        Button(action: {
                            if identityManager.isRecordingEnrollment {
                                identityManager.cancelCalibration()
                            } else {
                                identityManager.startCalibratingPartner()
                            }
                        }) {
                            HStack {
                                Image(systemName: identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForPartner ? "stop.circle.fill" : "mic.fill")
                                    .foregroundColor(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForPartner ? .red : .orange)
                                VStack(alignment: .leading) {
                                    Text(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForPartner ? "Stop & Save (Recording...)" : "Record Partner Voice (5s)")
                                         .foregroundColor(identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForPartner ? .red : .primary)
                                    if identityManager.isRecordingEnrollment && identityManager.calibrationState == .listeningForPartner {
                                        Text("Ask partner to speak...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .disabled(identityManager.calibrationState == .uncalibrated || identityManager.calibrationState == .listeningForUser)
                    }
                }
                
                if case .error(let msg) = identityManager.calibrationState {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(msg)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                if identityManager.calibrationState == .calibrated {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title)
                            Text("Calibration Complete")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Voice Setup")
        }
    }
}

struct ChatBubble: View {
    let text: String
    let speaker: Int
    let isPending: Bool
    
    var isUser: Bool {
        return speaker == 0
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer() }
            
            if !isUser {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 32, height: 32)
                    .overlay(Text("\(speaker)").font(.caption).foregroundColor(.white))
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(text)
                    .padding(12)
                    .background(isUser ? Color.blue.opacity(0.9) : Color(.systemGray5).opacity(0.9))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(16)
                    .opacity(isPending ? 0.7 : 1.0)
                
                if isPending {
                    Text("Speaking...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if isUser {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                    .overlay(Text("0").font(.caption).foregroundColor(.white))
            }
            
            if !isUser { Spacer() }
        }
    }
}
