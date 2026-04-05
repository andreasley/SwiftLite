@MainActor
public protocol AutoupdatingModel
{
    func _beginAutoupdating()
    func _update(with: ChangedObject) async throws
}
