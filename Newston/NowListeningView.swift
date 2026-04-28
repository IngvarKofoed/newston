import SwiftUI

struct NowListeningView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "headphones")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
                Text("Now Listening")
                    .font(.title2)
                Text("Voice-driven listening will land here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Now Listening")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NowListeningView()
}
