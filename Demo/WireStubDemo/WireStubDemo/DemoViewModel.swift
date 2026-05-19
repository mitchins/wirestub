import Foundation

@MainActor
final class DemoViewModel: ObservableObject {
    @Published private(set) var title = "Logged Out"
    @Published private(set) var subtitle = "Tap Log In to load your feed."
    @Published private(set) var isLoading = false

    private let client: DemoAPIClient
    private var hasAttemptedBootstrap = false

    init(client: DemoAPIClient = DemoAPIClient()) {
        self.client = client
    }

    func restoreSessionIfNeeded() {
        guard !hasAttemptedBootstrap else { return }
        hasAttemptedBootstrap = true
        guard client.hasCachedSession else { return }

        isLoading = true
        title = "Restoring Session..."
        subtitle = "Using consumer-owned bootstrap state."

        Task {
            do {
                switch try await client.restoreSeededSession() {
                case .feedReady(let result):
                    title = "Feed Ready"
                    subtitle = "Welcome \(result.userName). \(result.feedMessage)"
                case .sessionExpired:
                    title = "Session Expired"
                    subtitle = "Cached session cleared. Please log in again."
                }
            } catch {
                title = "Request Failed"
                subtitle = error.localizedDescription
            }

            isLoading = false
        }
    }

    func logIn() {
        guard !isLoading else { return }

        isLoading = true
        title = "Logging In..."
        subtitle = "Talking to the configured API base URL."

        Task {
            do {
                let result = try await client.runLoginFlow()
                title = "Feed Ready"
                subtitle = "Welcome \(result.userName). \(result.feedMessage)"
            } catch {
                title = "Request Failed"
                subtitle = error.localizedDescription
            }

            isLoading = false
        }
    }
}
