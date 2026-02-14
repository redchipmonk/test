import SwiftUI
import RealityKit
import RealityKitContent
import OSLog

struct ContentView: View {
    @Bindable var viewModel: ContentViewModel
    
    var body: some View {
        ZStack {
            TabView(selection: $viewModel.selectedTab) {
                // MARK: - Transcribe Tab
                transcribeView
                    .tabItem {
                        Label("Transcribe", systemImage: "mic.fill")
                    }
                    .tag(Tab.transcribe)
                
                // MARK: - History Tab
                SavedConversationsView(store: viewModel.getStore())
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(Tab.history)
            }
            .background(.clear)
            
            if viewModel.isInitializing {
                LoadingView()
            }
        }
        .task {
            Logger(subsystem: "team1.blubble", category: "ContentView").info("ContentView .task started")
            await viewModel.initialize()
            Logger(subsystem: "team1.blubble", category: "ContentView").info("ContentView .task finished")
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
                        .fill(viewModel.isRunning ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(viewModel.isRunning ? "Transcribing..." : "Ready")
                        .font(.headline)
                        .foregroundStyle(viewModel.isRunning ? .primary : .secondary)
                }
                
                Spacer()
                
                // Action buttons (shown when not recording and has messages)
                if !viewModel.isRunning && !viewModel.chatHistory.isEmpty {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.saveConversation()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive) {
                            viewModel.clearConversation()
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
                        ForEach(viewModel.chatHistory) { message in
                            ChatBubble(text: message.text, speaker: message.speaker, isPending: false)
                                .id(message.id)
                        }
                        
                        // Pending message
                        if !viewModel.transcript.isEmpty {
                            ChatBubble(
                                text: viewModel.transcript,
                                speaker: Int(viewModel.currentSpeaker?.components(separatedBy: " ").last ?? "") ?? 0,
                                isPending: true
                            )
                            .id("pending")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.chatHistory) { oldValue, newValue in
                    if let lastId = newValue.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.transcript) {
                    withAnimation {
                        proxy.scrollTo("pending", anchor: .bottom)
                    }
                }
            }
            
            Spacer()
            
            // Active Speaker Indicator (Sortformer)
            if viewModel.isRunning {
                VStack {
                    Text("Active: \(viewModel.currentSpeaker ?? "None")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Simple viz of 4 slots
                    HStack(spacing: 4) {
                        ForEach(0..<4) { index in
                            let prob = viewModel.speakerProbabilities.indices.contains(index) ? viewModel.speakerProbabilities[index] : 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(prob > 0.5 ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 20, height: CGFloat(max(4, prob * 20)))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            
            // Large Start/Stop Button
            Button(action: {
                if viewModel.isRunning {
                    viewModel.stopMonitoring()
                } else {
                    viewModel.startMonitoring()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "mic.fill")
                        .font(.title2)
                    Text(viewModel.isRunning ? "Stop Transcribing" : "Start Transcribing")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(viewModel.isRunning ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            .padding()
        }
        .background(.clear)
        .alert("Conversation Saved", isPresented: $viewModel.showingSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your conversation has been saved to History.")
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
