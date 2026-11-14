import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let library: LibraryStore
    let recorder: SegmentRecorder
    let transcription = TranscriptionService()
    let connectivity: PhoneConnectivity

    init() {
        let library = LibraryStore()
        self.library = library
        let recorder = SegmentRecorder(directory: library.audioDirectory, source: "iPhone")
        recorder.onSegment = { try library.add($0) }
        self.recorder = recorder
        connectivity = PhoneConnectivity(store: library)
    }
}

@main
struct DayEchoApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            TabView {
                LibraryView().tabItem { Label("记录", systemImage: "waveform") }
                AssistantView().tabItem { Label("回顾", systemImage: "sparkles") }
                SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }
            }
            .tint(.teal)
            .environmentObject(model.library)
            .environmentObject(model.recorder)
            .environmentObject(model.transcription)
        }
    }
}
