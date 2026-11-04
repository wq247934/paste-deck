import Foundation

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/zoefix/agent-speed")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? version
    }
}
