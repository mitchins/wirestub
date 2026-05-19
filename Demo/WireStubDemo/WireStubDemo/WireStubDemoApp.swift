import SwiftUI

@main
struct WireStubDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: DemoViewModel())
        }
    }
}
