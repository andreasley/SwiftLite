public actor AsyncStreams<Element: Sendable>
{
    public typealias Continuation = AsyncStream<Element>.Continuation
    
    private var continuations: Set<Continuation> = []
    private var lastElement: Element? = nil

    public func stream() async -> AsyncStream<Element>
    {
        var newContinuation: Continuation?
        let stream = AsyncStream { continuation in
            newContinuation = continuation
            continuations.insert(continuation)
            if let lastElement {
                continuation.yield(lastElement)
            }
        }

        if let newContinuation {
            newContinuation.onTermination = { _ in
                Task {
                    await self.remove(continuation: newContinuation)
                }
            }
        }
        
        return stream
    }
    
    public func remove(continuation: Continuation)
    {
        continuation.finish()
        continuations.remove(continuation)
    }

    nonisolated func yield(_ element: Element)
    {
        Task {
            await broadcast(element)
        }
    }
    
    private func broadcast(_ element: Element)
    {
        self.lastElement = element
        for continuation in continuations {
            continuation.yield(element)
        }
    }

    public nonisolated func finish()
    {
        Task {
            await finishAll()
        }
    }
    
    private func finishAll()
    {
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
