import SwiftUI
import BibleFeedKit

struct OnboardingView: View {
    let state: UserState

    @State private var chosen: Set<Topic>

    init(state: UserState) {
        self.state = state
        _chosen = State(initialValue: state.topics)
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private var canContinue: Bool { (3...5).contains(chosen.count) }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("What's on your mind?")
                    .font(.largeTitle.bold())
                Text("Pick three to five. We'll start there.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Topic.allCases, id: \.self) { topic in
                    Button {
                        toggle(topic)
                    } label: {
                        Text(topic.rawValue.capitalized)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(chosen.contains(topic) ? Color.accentColor : Color(.secondarySystemBackground))
                    .foregroundStyle(chosen.contains(topic) ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Continue") {
                    state.setTopics(chosen)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canContinue)

                Button("Skip for now") {
                    state.setTopics([])
                }
                .font(.footnote)
            }
        }
        .padding(24)
    }

    private func toggle(_ topic: Topic) {
        if chosen.contains(topic) {
            chosen.remove(topic)
        } else if chosen.count < 5 {
            chosen.insert(topic)
        }
    }
}
