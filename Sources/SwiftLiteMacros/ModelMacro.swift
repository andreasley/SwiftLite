import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct ModelMacro: MemberMacro
{
    enum Error: Swift.Error, CustomStringConvertible {
        case notAClass
        
        var description: String {
            switch self {
            case .notAClass:
                return "The target must be a class."
            }
        }
    }
    
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, in context: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        var propertyNames: [String] = []
        
        for member in declaration.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard varDecl.bindings.count == 1, varDecl.bindings.first?.accessorBlock == nil else { continue }
            if let name = varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                propertyNames.append(name)
            }
        }
        
        let arrayElements = propertyNames
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        
        let fieldsDecl: DeclSyntax =
        """
        static let fields = [\(raw: arrayElements)]
        """

        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw Error.notAClass
        }
        
//        let tablePath = qualifiedName(of: declaration)
//
//        let tableName = classNameToTableName(classDecl.name.text)
//        let tableDecl: DeclSyntax = """
//        static let table = "\(raw: tablePath)"
//        """
        

//        guard let inner = nominalName(of: declaration) else { return [] }
//
//        let outers = allEnclosingNominalNames(startingAt: Syntax(declaration))
//        let allParts = (outers + [inner]).map { $0.lowercased() }
//        let tableName = allParts.joined(separator: "__")

        let tableName = try createTableNameFromQualifiedName(of: classDecl, in: context)
        let member: DeclSyntax =
        """
        static let table = "\(raw: tableName)"
        """

        return [member, fieldsDecl]
    }

    static func createTableNameFromQualifiedName(of declaration: ClassDeclSyntax, in context: MacroExpansionContext) throws -> String
    {
        var components: [String] = [declaration.name.text]

        for parent in context.lexicalContext {
            guard let named = parent.asProtocol(NamedDeclSyntax.self) else { continue }
            components.insert(named.name.text, at: 0)
        }

        let sanitizedTableName = try SQLiteHelpers.generateTableName(components)
        return sanitizedTableName
    }
}
