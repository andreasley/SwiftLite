import Foundation

extension URL
{
    func createParentDirectoryIfNotExists() throws
    {
        let directoryUrl = self.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
    }
    
    var exists: Bool {
        FileManager.default.fileExists(atPath: self.path(percentEncoded: false))
    }
    
    var filePath: String {
        self.path(percentEncoded: false)
    }
}
