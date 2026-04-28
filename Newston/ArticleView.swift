import SwiftUI
import SwiftData

struct ArticleView: View {
    @Environment(NowListeningPlayer.self) private var player
    let headline: Headline

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(headline.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let host = headline.source?.url.host() {
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    bodyContent
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            transportControls
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VoiceTranscriptStatus()
                .padding(.bottom, 4)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { MicToolbarButton() }
        }
        .task {
            await player.didEnterArticle(headline: headline)
        }
        .onDisappear {
            player.didLeaveArticle()
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if player.isLoadingArticle {
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading article…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical)
        } else if let body = player.currentArticleBody, !body.isEmpty {
            Text(body)
                .font(.body)
                .textSelection(.enabled)
        } else if let error = player.articleError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't load article", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical)
        }
    }

    private var transportControls: some View {
        HStack {
            Spacer()
            Button {
                player.togglePauseResume()
            } label: {
                Image(systemName: playPauseIcon)
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(playPauseDisabled)
            .accessibilityLabel(playPauseLabel)
            Spacer()
        }
    }

    private var playPauseIcon: String {
        switch player.speechState {
        case .speaking: return "pause.circle.fill"
        case .paused, .idle: return "play.circle.fill"
        }
    }

    private var playPauseLabel: String {
        switch player.speechState {
        case .speaking: return "Pause reading"
        case .paused: return "Resume reading"
        case .idle: return "Start reading"
        }
    }

    private var playPauseDisabled: Bool {
        switch player.speechState {
        case .speaking, .paused: return false
        case .idle:
            return player.currentArticleBody == nil || player.isLoadingArticle
        }
    }
}
