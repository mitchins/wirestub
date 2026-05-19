import Foundation

/// Minimal launch-environment surface needed to configure an app under test without importing XCTest into server code.
public protocol WireStubLaunchConfigurable: AnyObject {
    /// Launch environment dictionary passed into the app process.
    var launchEnvironment: [String: String] { get set }
}
