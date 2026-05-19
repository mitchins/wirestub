import Foundation

/// Shared path constants used to avoid repeated hard-coded separators in transport adapters.
public enum PathUtilities {
    /// The canonical root path (`/`).
    public static let rootPath = String(decoding: [UInt8(47)], as: UTF8.self)
}
