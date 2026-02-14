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
                            ChatBubble(text: message.text, speaker: message.speaker, isPending: false, emotion: message.emotion)
                                .id(message.id)
                        }
                        
                        // Pending message
                        if !viewModel.transcript.isEmpty {
                            ChatBubble(
                                text: viewModel.transcript,
                                speaker: Int(viewModel.currentSpeaker?.components(separatedBy: " ").last ?? "") ?? 0,
                                isPending: true,
                                emotion: Emotion.neutral
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



struct ViolentShake: ViewModifier {
    var trigger: Bool
    
    func body(content: Content) -> some View {
        content
            .keyframeAnimator(
                initialValue: CGSize.zero,
                trigger: trigger
            ) { view, offset in
                view.offset(offset)
            } keyframes: { _ in
                KeyframeTrack(\.width) {
                    LinearKeyframe( 22, duration: 0.056)
                    LinearKeyframe(-24, duration: 0.070)
                    LinearKeyframe( 15, duration: 0.044)
                    LinearKeyframe(-18, duration: 0.062)
                    LinearKeyframe(  8, duration: 0.052)
                    LinearKeyframe(  0, duration: 0.090)
                }

                KeyframeTrack(\.height) {
                    LinearKeyframe(-14, duration: 0.042)
                    LinearKeyframe( 17, duration: 0.076)
                    LinearKeyframe(-11, duration: 0.054)
                    LinearKeyframe(  9, duration: 0.068)
                    LinearKeyframe( -4, duration: 0.040)
                    LinearKeyframe(  0, duration: 0.100)
                }
            }
    }
}

extension View {
    func violentShake(trigger: Bool) -> some View {
        modifier(ViolentShake(trigger: trigger))
    }
}
