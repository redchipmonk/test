# Blubble - AR Conversation Companion

**Blubble** is an augmented reality (AR) heads-up display (HUD) designed for the Apple Vision Pro to augment human interaction in 1-on-1 settings. Built as a university capstone project, Blubble visualizes speech, tone, and contextual information in real-time to reduce cognitive load and make conversations more accessible—specifically designed to aid neurodivergent users and those with working memory deficits.

## Project Architecture

To support parallel development across a four-person team, Blubble strictly adheres to **MVVM (Model-View-ViewModel)** and **Protocol-Oriented Dependency Injection**. This ensures that UI, business logic, and hardware services can be built and tested independently.

### Directory Structure

* **`Models/`**: Pure data structures and SwiftData/Codable models (e.g., `ChatMessage`, `Conversation`).
* **`ViewModels/`**: The `@MainActor` classes that manage state and contain application logic (e.g., `ContentViewModel`). ViewModels should *never* import `RealityKit` or contain UI layout code.
* **`Views/`**: SwiftUI and RealityKit views. These should be as "dumb" as possible, strictly observing ViewModels and routing user intents.
* **`Managers/` (Services)**: Specialized, single-responsibility classes that handle hardware, network, or ML tasks. 
    * *All services must implement a Protocol* (e.g., `AudioCaptureProtocol`, `SpeechRecognitionProtocol`).

## Development Guidelines

As a team, we follow these core engineering principles:

### 1. Dependency Injection (No Singletons)
Do not use `Manager.shared`. All services must be instantiated at the root level in `blubbleApp.swift` (our Composition Root) and passed down into ViewModels or other services via their initializers using Protocols. This allows us to inject mock services (like a `MockAudioCaptureService`) so we can build SwiftUI Previews and run automated tests without needing to connect to the physical Vision Pro microphone or the Deepgram API.

### 2. Single Responsibility Principle (SRP)
If a class is doing more than one thing, split it. For example, capturing audio (`AVAudioEngine`) and parsing WebSocket JSON (`URLSession`) are two different jobs and live in two different services.

### 3. Modern Concurrency
Do not use completion handlers (`@escaping`). Use modern Swift Concurrency (`async/await`, `Task`, `AsyncStream`). Always ensure UI updates and ViewModel state changes are routed to the Main Thread using `@MainActor`.

### 4. Branching Strategy
* `main` is protected and always deployable.
* Create feature branches: `feature/transcription-ui`, `bugfix/audio-crash`, `chore/refactor-models`.
* All PRs require at least one code review before merging.

## Secrets Management

**NEVER commit API keys to version control.**

Blubble relies on external APIs like Deepgram. To run the project locally, you must set up your secrets file:
1. Locate `Secrets-Template.plist` (if available) or create a new file named `Secrets.plist` in the root directory.
2. Add your Deepgram API key:
   ```xml
   <key>DeepgramAPIKey</key>
   <string>YOUR_API_KEY_HERE</string>