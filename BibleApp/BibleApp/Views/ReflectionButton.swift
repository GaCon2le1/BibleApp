import SwiftUI

/// Starts a timed reflection session on the Lock Screen, or shows the
/// running one with a way to end it.
struct ReflectionButton: View {
    /// Verse ids for the session, starting at the verse on screen.
    let ids: () -> [String]

    @State private var isChoosingDuration = false
    private let session = ReadingSessionController.shared

    var body: some View {
        Group {
            if let endDate = session.activeEndDate, endDate > .now {
                Button {
                    Task { await session.end() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(timerInterval: Date.now...endDate, countsDown: true)
                            .monospacedDigit()
                        Text("· End")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
                .accessibilityLabel("End reflection session")
            } else {
                Button {
                    isChoosingDuration = true
                } label: {
                    Image(systemName: "timer")
                }
                .accessibilityLabel("Start reflection session")
            }
        }
        .font(.subheadline.weight(.semibold))
        .confirmationDialog("Reflection session",
                            isPresented: $isChoosingDuration,
                            titleVisibility: .visible) {
            ForEach([5, 10, 15], id: \.self) { minutes in
                Button("\(minutes) minutes") {
                    let sessionIDs = ids()
                    Task { await session.start(minutes: minutes, ids: sessionIDs) }
                }
            }
        } message: {
            Text("Keep reading on your Lock Screen until the timer ends.")
        }
        .alert("Reflection session",
               isPresented: Binding(get: { session.alertMessage != nil },
                                    set: { if !$0 { session.alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.alertMessage ?? "")
        }
    }
}
