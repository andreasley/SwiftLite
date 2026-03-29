import Foundation

public nonisolated protocol SQLExpression: Hashable, Equatable, Sendable
{
    var text: String { get }
    var values: [SQLValue] { get }
}

public nonisolated extension SQLExpression
{
    static func byId(_ id: UUID) -> SQLCondition
    {
        .init(field: "id", value: .string(id.storageValue))
    }

    static func byParent(_ id: UUID) -> SQLCondition
    {
        .init(field: "parent", value: .string(id.storageValue))
    }

    static func byElement(_ id: UUID) -> SQLCondition
    {
        .init(field: "element", value: .string(id.storageValue))
    }
}
