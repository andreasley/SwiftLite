public protocol ActorNotificationProxy
{
    func onChange(changeset: FrozenChangeset)
}
