import Foundation

nonisolated extension URL
{
    static func databaseFilesDirectory(for databaseIdentifier: String) -> URL
    {
        let appSupportURL = URL.applicationSupportDirectory
        let applicationDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "SwiftLiteWebSyncTester", isDirectory: true)
        let databaseFilesDirectory = applicationDirectory.appendingPathComponent(databaseIdentifier, isDirectory: true)
        return databaseFilesDirectory
    }
}
