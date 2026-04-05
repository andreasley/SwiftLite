extension Database: Hashable
{
    public nonisolated func hash(into hasher: inout Hasher)
    {
        hasher.combine(ObjectIdentifier(self))
    }
}
