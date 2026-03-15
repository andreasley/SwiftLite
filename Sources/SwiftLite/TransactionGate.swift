actor TransactionGate
{
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var isRunning = false

    private func acquire() async
    {
        if isRunning {
            await withCheckedContinuation { pending.append($0) }
        }
        isRunning = true
    }

    private func release()
    {
        if let next = pending.first {
            pending.removeFirst()
            next.resume()
        } else {
            isRunning = false
        }
    }
    
    @discardableResult
    func run<T>(_ body: () async throws -> T, isolation: isolated (any Actor)? = #isolation) async rethrows -> T
    {
        await acquire()
        defer { Task { await release() }}
        let result = try await body()
        await release()
        return result
    }
}
