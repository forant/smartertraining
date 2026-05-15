import SwiftUI

struct StravaPostView: View {
    let workout: CompletedWorkout
    var onPosted: () -> Void

    @State private var auth = StravaAuth()
    @State private var uploader: StravaUploader?
    @State private var isAuthorizing = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 16) {
            if !StravaConfig.isConfigured {
                notConfiguredView
            } else if !auth.isConnected {
                connectView
            } else {
                uploadView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Not Configured

    private var notConfiguredView: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)
            Text("Strava posting available after API setup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connect

    private var connectView: some View {
        VStack(spacing: 12) {
            if let authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    isAuthorizing = true
                    authError = nil
                    do {
                        try await auth.authorize()
                        uploader = StravaUploader(auth: auth)
                    } catch {
                        authError = error.localizedDescription
                    }
                    isAuthorizing = false
                }
            } label: {
                HStack {
                    Image(systemName: "link")
                    Text("Connect to Strava")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)
            .disabled(isAuthorizing)

            if isAuthorizing {
                ProgressView("Connecting...")
                    .font(.caption)
            }
        }
    }

    // MARK: - Upload

    private var uploadView: some View {
        VStack(spacing: 12) {
            if let uploader {
                switch uploader.state {
                case .idle:
                    postButton
                case .uploading:
                    ProgressView("Uploading...")
                        .font(.subheadline)
                case .processing:
                    ProgressView("Processing...")
                        .font(.subheadline)
                case .success:
                    successView
                case .failed(let message):
                    failedView(message)
                }
            } else {
                postButton
            }

            if let name = auth.athleteName {
                HStack {
                    Text("Connected as \(name)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Disconnect") {
                        auth.disconnect()
                        uploader = nil
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var postButton: some View {
        Button {
            if uploader == nil {
                uploader = StravaUploader(auth: auth)
            }
            Task {
                await uploader?.upload(workout: workout)
                if case .success = uploader?.state {
                    onPosted()
                }
            }
        } label: {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                Text("Post to Strava")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.orange)
        .disabled(workout.isPostedToStrava)
    }

    private var successView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("It happened.")
                    .font(.headline)
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Strava didn't take it. Try again?")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                uploader?.reset()
                Task { await uploader?.upload(workout: workout) }
            } label: {
                Text("Retry")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)
        }
    }
}
