import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: DemoViewModel

    init(viewModel: DemoViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(viewModel.title)
                .font(.title2)
                .accessibilityIdentifier("statusTitle")

            Text(viewModel.subtitle)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("statusSubtitle")

            Button("Log In") {
                viewModel.logIn()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("loginButton")

            if viewModel.isLoading {
                ProgressView()
                    .accessibilityIdentifier("loadingIndicator")
            }
        }
        .padding(24)
        .task {
            viewModel.restoreSessionIfNeeded()
        }
    }
}

#Preview {
    ContentView(viewModel: DemoViewModel())
}
