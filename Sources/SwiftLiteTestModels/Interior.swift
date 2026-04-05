import SwiftLite
import Foundation

@Model public final class Interior
{
    @SnapshotCompatible
    nonisolated(nonsending) func foo() async throws -> Int
    {
        Int.random(in: 0..<100)
    }
    
    @Transient
    var blubb: Int = 0
    
    @Stored(isUnique: true)
    let name: String
}
