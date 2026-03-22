import Foundation

public nonisolated struct PropertyChange<T: Model, V: SQLValueConvertible>: AnyPropertyChange
{
    let date = Date.now
    let id = UUID.v7()
    let keyPath: KeyPath<T, V>
    let value: V
    
    public var sqlValue: SQLValue {
        value.convertToSQLValue()
    }
}
