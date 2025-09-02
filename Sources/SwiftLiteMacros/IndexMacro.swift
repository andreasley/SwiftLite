import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics


extension SyntaxProtocol {
  func ancestor<T: SyntaxProtocol>(_ type: T.Type) -> T? {
    var node: Syntax? = Syntax(self)
    while let cur = node {
      if let t = cur.as(T.self) { return t }
      node = cur.parent
    }
    return nil
  }
}

public struct IndexMacro: DeclarationMacro
{
    enum Error: Swift.Error, CustomStringConvertible {
        case message(String)
        var description: String {
            switch self {
            case .message(let s): return s
            }
        }
    }
    
    static func getQualifiedTypeName(in context: MacroExpansionContext) -> String?
    {
        var components: [String] = []
        
        for parent in context.lexicalContext {
            guard let named = parent.asProtocol(NamedDeclSyntax.self) else { continue }
            components.insert(named.name.text, at: 0)
        }
        
        return components.joined(separator: ".")
    }

    
    public static func expansion(of node: some SwiftSyntax.FreestandingMacroExpansionSyntax, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.DeclSyntax] {

        guard let typeName = getQualifiedTypeName(in: context) else {
            context.diagnose(Diagnostic(node: Syntax(node), message: SimpleMessage(message: "Failed to find class name.")))
            return []
        }

        // Collect expressions from the trailing closure body
        var elements: [String] = []
        if let closure = node.trailingClosure {
            for item in closure.statements {
                if let expr = item.item.as(ExprSyntax.self) {
                    elements.append(expr.trimmedDescription)
                } else if let exprStmt = item.item.as(ExpressionStmtSyntax.self) {
                    elements.append(exprStmt.expression.trimmedDescription)
                }
            }
        }
        
        guard !elements.isEmpty else {
            context.diagnose(Diagnostic(
                node: Syntax(node),
                message: SimpleMessage(message: "`#Index { ... }` requires one or more expressions in the closure.")
            ))
            return []
        }
        
        let payload = elements.joined(separator: ", ")
        
        // Emit: static let customIndexes: [CompositeIndex<Car>] = [ ... ]
        let decl: DeclSyntax = """
      static let customIndexes: [CompositeIndex<\(raw: typeName)>] = [\(raw: payload)]
      """
        
        return [decl]
    }
    
    
    //    public static func expansion(
    //        of node: some FreestandingMacroExpansionSyntax,
    //        in context: some MacroExpansionContext
    //    ) throws -> ExprSyntax {
    //
    //        // Expect: #Index(on: [\Type.prop, \Type.other])
    //        let argList = node.arguments
    //        guard let onArg = argList.first(where: { $0.label?.text == "on" }),
    //              let array = onArg.expression.as(ArrayExprSyntax.self)
    //        else {
    //            throw Error.message("Use #Index(on: [\\Type.prop, ...])")
    //        }
    //
    //        // Parse the key-paths, extracting the final component name ("prop")
    //        var pairs: [String] = []
    //
    //        for element in array.elements {
    //            let expr = element.expression.trimmed
    //            guard let keyPath = expr.as(KeyPathExprSyntax.self) else {
    //                throw Error.message("Expected a key path like \\Self.prop or \\.prop")
    //            }
    //
    //
    //            guard
    //                let propertyName = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text,
    //                  !propertyName.isEmpty
    //            else {
    //                throw Error.message("Could not extract property name from \(keyPath.description)")
    //            }
    //
    //            let pair = #""\#(propertyName)": \Self.\#(propertyName)"#
    //            pairs.append(pair)
    //        }
    //
    //        // Compose: CompositeIndex<Self>(["name": \.name, "year": \.year])
    //        let dictBody = pairs.joined(separator: ", ")
    //        let expansion = "CompositeIndex(columns: [\(dictBody)])"
    //        return ExprSyntax(stringLiteral: expansion)
    //    }
    
    struct SimpleMessage: DiagnosticMessage {
        let message: String
        var diagnosticID: MessageID { .init(domain: "IndexMacro", id: "error") }
        var severity: DiagnosticSeverity { .error }
    }
}

