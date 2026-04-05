public nonisolated protocol WithModelLifecycleFunctions
{
    func afterInit()
    nonisolated(nonsending) func beforeSave() async throws
    func afterSave()
}
