import SwiftUI

@main
struct MeetingTranscriberApp: App {
    @StateObject private var apiConfiguration = APIConfiguration()
    @StateObject private var historyViewModel = MeetingHistoryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiConfiguration)
                .environmentObject(historyViewModel)
        }
    }
}
