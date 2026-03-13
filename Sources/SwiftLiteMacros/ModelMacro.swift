import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct ModelMacro: MemberMacro, ExtensionMacro, MemberAttributeMacro
{
    
    // MARK: MemberAttributeMacro
    
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingAttributesFor member: some SwiftSyntax.DeclSyntaxProtocol,
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.AttributeSyntax]
    {
        
        // Check if the member is a variable declaration
        guard let varDecl = member.as(VariableDeclSyntax.self) else {
            return []
        }
        
        // Check if it's a 'var' (not 'let')
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []
        }
        
        // Check if @Backed is already applied
        let hasAttribute = varDecl.attributes.contains { attribute in
            guard case let .attribute(attr) = attribute else { return false }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Backed"
        }
        
        if hasAttribute {
            return []
        }
        
        var declarations = [SwiftSyntax.AttributeSyntax]()
        
        declarations.append(AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("Backed"))))
        
        let hasObservable = declaration.attributes.contains { attribute in
            guard case let .attribute(attr) = attribute else { return false }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Observable"
        }
        
        if hasObservable {
            // Add `@ObservationIgnored` to prevent `@Observable` adding `@ObservationTracked`, which adds a getter/setter (thereby conflicting with the getter/setter added by SwiftLite's `@Backed`.
            declarations.append(AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("ObservationIgnored"))))
        }

        return declarations
    }
    
    static let primaryKeyFieldName = "id"
    static let databaseReferencePropertyName = "db"

    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.ExtensionDeclSyntax]
    {
        var generatedExtensions = [SwiftSyntax.ExtensionDeclSyntax]()
        
        // MARK: SwiftLite.Model
        
        let modelProtocol: TypeSyntax = "SwiftLite.Model"
        
        if !protocols.contains(where: { $0.trimmedDescription == modelProtocol.trimmedDescription }) {
            if let modelExtensionDecl = ExtensionDeclSyntax(DeclSyntax(stringLiteral: "extension \(type): \(modelProtocol) {}")) {
                generatedExtensions.append(modelExtensionDecl)
            }
        }
        
        // TODO: Move stuff for conformance to SwiftLite.Model to here
        
        return generatedExtensions
    }
    
    enum ModelFixItMessage: String, FixItMessage {
        case removeDefaultValue
        
        var message: String {
            switch self {
            case .removeDefaultValue:
                "Remove default value."
            }
        }
        
        var fixItID: MessageID {
            MessageID(domain: "ModelMacro", id: self.rawValue)
        }
    }
    
    enum ErrorMessage: String, DiagnosticMessage {
        case duplicateInitializer
        case notAClass
        case unexpectedPropertyDefaultValue
        case unexpectedMultipleBindings
        case unexpectedBindingPattern
        case failedToFindType
        case failedToGenerateColumnName
        case invalidDefaultValue
        case literalExpected
        
        var message: String {
            switch self {
            case .duplicateInitializer:
                "SwiftLite Models aren't allowed to have a custom default initializer. Use convenience initializers instead."
            case .notAClass:
                "SwiftLite Model must be a class."
            case .unexpectedPropertyDefaultValue:
                "Properties in a SwiftLite Model must not have a default value. Annotate the property with `@Default()` or use a convenience initializer."
            case .unexpectedMultipleBindings:
                "Properties in a SwiftLite Model must not have multiple bindings."
            case .unexpectedBindingPattern:
                "Properties in a SwiftLite Model must define the name of a single variable."
            case .failedToFindType:
                "Properties in a SwiftLite Model must have a type specified."
            case .failedToGenerateColumnName:
                "Failed to generate column name from property name."
            case .invalidDefaultValue:
                "Invalid default value format. Default value attributes must have the format  `@DefaultValue(<preferredValue>)`."
            case .literalExpected:
                "Literal expected; expressions aren't allowed here."
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "ModelMacro", id: self.rawValue)
        }
        
        var severity: DiagnosticSeverity {
            .error
        }
    }
    
    static public func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax]
    {
        var diagnostics: [Diagnostic] = []
        var generatedDeclarations: [DeclSyntax] = []
        
        
        // MARK: Check object type
        // Check if the annotated object is a `class` (which is the only supported nominal type)
        
        let classDecl = declaration.as(ClassDeclSyntax.self)
        if classDecl == nil {
            diagnostics.append(Diagnostic(node: declaration, message: ErrorMessage.notAClass))
        }
        
        // MARK: Generate table name
        
        // TODO: Check if there's already a `static let tableName: String`. If so, that should be used instead of a generated one. Or use a parameter on the `@Model()`?
        let tableName = createTableNameFromQualifiedName(of: classDecl, in: context)
//        let tableName = classDecl?.name.text
        

        // MARK: Database reference
        // TODO: Check if there's already a property `db`; warn if so
        
        let dbDecl: DeclSyntax =
        """
        let db: SwiftLite.Database
        """
        generatedDeclarations.append(dbDecl)

        
        // MARK: ID
        // TODO: Check if there's already a property `id`; warn if so
        
        let idDecl: DeclSyntax =
        """
        let id: UUID
        """
        generatedDeclarations.append(idDecl)

        
        // MARK: Entity
        // The entity details are required in the compiled app to check the schema and execute migrations if necessary.
        
        let properties = getProperties(from: declaration, diagnostics: &diagnostics)
        
        addStaticStoredVariablesForDefaultValues(from: properties, to: &generatedDeclarations)
        
        if let tableName {
            let columnsStructDecl = getColumnsStruct(properties: properties)
            generatedDeclarations.append(columnsStructDecl)

            let tableDeclaration = getSchemaTable(tableName: tableName, properties: properties)
            generatedDeclarations.append(tableDeclaration)

            let defaultSelectStatement: DeclSyntax =
            """
            static let __defaultSelectStatement: String = "SELECT \(raw: properties.filter({ !$0.isRelated }).map({ $0.columnName.description }).joined(separator: ",")) FROM \(raw: tableName)"
            """
            generatedDeclarations.append(defaultSelectStatement)
        }

        // MARK: Tracking value changes
        
        if let className = classDecl?.name.description {
            let changeCollectionDecl: DeclSyntax =
            """
            private var _changes = ObjectChangelog<\(raw: className)>()
            """

            generatedDeclarations.append(changeCollectionDecl)
        } else {
            // TODO: Show error
        }
        
        // MARK: Nested backing class for stored properties and support for observation
        
        generatedDeclarations.append(getBackingDecl(properties: properties))

        
        //        var newMembers: [DeclSyntax] = []
//
//        for member in declaration.memberBlock.members
//        {
//            guard let variable = member.decl.as(VariableDeclSyntax.self),
//                  variable.bindingSpecifier.tokenKind == .keyword(.var),
//                  !variable.modifiers.contains(where: { $0.name.text == "private" && $0.name.text.hasPrefix("_") })
//            else {
//                continue
//            }
//            
//            for binding in variable.bindings {
//                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
//                      let type = binding.typeAnnotation?.type
//                else {
//                    continue
//                }
//                
//                let propertyName = identifier.identifier.text
//                let propertyType = type.trimmedDescription
//                let backingName = "_\(propertyName)"
//                
//                // Create backing storage
//                newMembers.append(
//                    """
//                    private var \(raw: backingName): \(raw: propertyType)
//                    """
//                )
//                
//                // Create computed property with change tracking
//                let computedProperty: DeclSyntax =
//                    """
//                    public var \(raw: propertyName): \(raw: propertyType) {
//                        get {
//                            return \(raw: backingName)
//                        }
//                        set {
//                            \(raw: backingName) = newValue
//                            _changes.append(PropertyChange(
//                                propertyName: "\(raw: propertyName)",
//                                value: newValue
//                            ))
//                        }
//                    }
//                    """
//                
//                newMembers.append(computedProperty)
//            }
//        }
//
        
        
        // MARK: Initializers
        
        // Check if there's already an initializer. If so, make a diagnostic (because it's necessary to generate the required initializers to properly handle read-only fields and the `id` property.
        if let initMember = declaration.memberBlock.members.first(where: { member in
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { return false }
            return !initDecl.modifiers.contains(where: { $0.name.text == "convenience" })
        }) {
            let diag = Diagnostic(node: initMember.decl, message: ErrorMessage.duplicateInitializer)
            diagnostics.append(diag)
        }
        
        let initNewDecl = initializerForNewObject(properties: properties)
        generatedDeclarations.append(DeclSyntax(initNewDecl))
        
        let initFromResultDecl = initializerForObjectFromDatabase(properties: properties, forMainModel: true)
        generatedDeclarations.append(DeclSyntax(initFromResultDecl))
        
        // MARK: Create Table statement
        
        // Note: The SQL `CREATE TABLE` statement is not generated by the Macro because type information is required for that (and Swift Macros operate on syntax only).
        
        // MARK: Read-only structs
        
        let snapshotTypealiasDecl: DeclSyntax =
        """
        typealias Snapshot = ReadOnlySnapshot
        """
        generatedDeclarations.append(snapshotTypealiasDecl)
        
        generatedDeclarations.append(getFlatDecl(properties: properties))

        let flatSnapshotTypealiasDecl: DeclSyntax =
        """
        typealias FlatSnapshot = ReadOnlyFlatSnapshot
        """
        generatedDeclarations.append(flatSnapshotTypealiasDecl)

        generatedDeclarations.append(getSnapshotDecl(properties: properties))

        return generatedDeclarations
    }
    
    static func getColumnsStruct(properties: [ModelConfiguration.Property]) -> DeclSyntax
    {
        let structName = "Columns"
        let memberDeclList = MemberBlockItemListSyntax {
            properties.map { property in

                let positionExpression: ExprSyntax
                if let position = property.positionInPrimaryKey {
                    positionExpression = ExprSyntax(IntegerLiteralExprSyntax(integerLiteral: position))
                } else {
                    positionExpression = ExprSyntax(NilLiteralExprSyntax())
                }
                
                let unwrappedTypeExpression = ExprSyntax(
                    MemberAccessExprSyntax(
                        base: TypeExprSyntax(type: property.unwrappedType),
                        declName: DeclReferenceExprSyntax(baseName: .keyword(.self))
                    )
                )
                
                // TODO: Make a decision if default values in SQLite are supported
                let defaultValueExpression: ExprSyntax
//                if let defaultValuePropertyName = property.defaultValuePropertyName {
//                    defaultValueExpression = ExprSyntax(
//                        MemberAccessExprSyntax(
//                            base: TypeExprSyntax(type: property.unwrappedType),
//                            declName: DeclReferenceExprSyntax(baseName: .init(stringLiteral: defaultValuePropertyName))
//                        )
//                    )
//                } else {
                    defaultValueExpression = ExprSyntax(NilLiteralExprSyntax())
//                }

                let functionCall = FunctionCallExprSyntax(
                    calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("Schema.Column"))),
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax {
                        LabeledExprSyntax(
                            label: .identifier("name"),
                            colon: .colonToken(),
                            expression: StringLiteralExprSyntax(content: property.name)
                        )
                        LabeledExprSyntax(
                            label: .identifier("type"),
                            colon: .colonToken(),
                            expression: unwrappedTypeExpression
                        )
                        LabeledExprSyntax(
                            label: .identifier("positionInPrimaryKey"),
                            colon: .colonToken(),
                            expression: positionExpression
                        )
                        LabeledExprSyntax(
                            label: .identifier("isNullable"),
                            colon: .colonToken(),
                            expression: ExprSyntax(literal: property.typeIsOptional)
                        )
                        LabeledExprSyntax(
                            label: .identifier("defaultValue"),
                            colon: .colonToken(),
                            expression: defaultValueExpression
                        )
                    },
                    rightParen: .rightParenToken()
                )

                let variableDecl = VariableDeclSyntax(
                    modifiers: [DeclModifierSyntax(name: .keyword(.static))],
                    bindingSpecifier: .keyword(.let),
                    bindingsBuilder: {
                        PatternBindingSyntax(
                            pattern: IdentifierPatternSyntax(
                                identifier: .identifier(property.name)
                            ),
                            initializer: InitializerClauseSyntax(
                                equal: .equalToken(),
                                value: ExprSyntax(functionCall)
                            )
                        )
                    }
                )

                let member: MemberBlockItemSyntax = MemberBlockItemSyntax(
                    decl: DeclSyntax(variableDecl),
                    semicolon: nil
                )
                
                return member
            }
        }

        let structDecl = StructDeclSyntax(
            name: .identifier(structName),
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: memberDeclList,
                rightBrace: .rightBraceToken()
            )
        )

        return DeclSyntax(structDecl)
    }
    
    static func getBackingDecl(properties: [ModelConfiguration.Property]) -> DeclSyntax
    {
        let structName = "BackingData"
        let initDecl = initializerForObjectFromDatabase(properties: properties, skipRelations: true, forMainModel: false, forBacking: true)
        let memberDeclList = MemberBlockItemListSyntax {
            for property in properties.filter({ $0.isVariable }) {
                MemberBlockItemSyntax(.var, name: property.name, type: property.type)
            }
            initDecl
        }

        let inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(),
            inheritedTypesBuilder: {
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Observable")))
                )
            }
        )

        let observableAttribute: AttributeSyntax = AttributeSyntax(atSign: .atSignToken(), attributeName: IdentifierTypeSyntax(name: .identifier("Observable")))

        let classDecl = ClassDeclSyntax(
            attributes: [.attribute(observableAttribute)],
            name: .identifier(structName),
            inheritanceClause: inheritanceClause,
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: memberDeclList,
                rightBrace: .rightBraceToken()
            )
        )

        return DeclSyntax(classDecl)
    }

    static func getFlatDecl(properties: [ModelConfiguration.Property]) -> DeclSyntax
    {
        let structName = "ReadOnlyFlatSnapshot"
        let initDecl = initializerForObjectFromDatabase(properties: properties, skipRelations: true, forMainModel: false)
        let memberDeclList = MemberBlockItemListSyntax {
            MemberBlockItemSyntax(.let, name: databaseReferencePropertyName, type: "SwiftLite.Database")
            for property in properties.filter({ $0.isRelated == false }) {
                MemberBlockItemSyntax(.let, name: property.name, type: property.type)
            }
            initDecl
        }

        let inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(),
            inheritedTypesBuilder: {
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))
                )
//                InheritedTypeSyntax(
//                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable")))
//                )
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("InitializableFromResultRow")))
                )
            }
        )

        let structDecl = StructDeclSyntax(
            name: .identifier(structName),
            inheritanceClause: inheritanceClause,
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: memberDeclList,
                rightBrace: .rightBraceToken()
            )
        )

        return DeclSyntax(structDecl)
    }

    static func getSnapshotDecl(properties: [ModelConfiguration.Property]) -> DeclSyntax
    {
        let structName = "ReadOnlySnapshot"
        let initDecl = initializerForObjectFromDatabase(properties: properties, forMainModel: false)
        let memberDeclList = MemberBlockItemListSyntax {
            MemberBlockItemSyntax(.let, name: databaseReferencePropertyName, type: "SwiftLite.Database")
            for property in properties {
                MemberBlockItemSyntax(.let, name: property.name, type: property.typeForConstantInSnapshot)
            }
            initDecl
        }

        let inheritanceClause = InheritanceClauseSyntax(
            colon: .colonToken(),
            inheritedTypesBuilder: {
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Sendable")))
                )
//                InheritedTypeSyntax(
//                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Codable")))
//                )
                InheritedTypeSyntax(
                    type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("InitializableFromResultRow")))
                )
            }
        )

        let structDecl = StructDeclSyntax(
            name: .identifier(structName),
            inheritanceClause: inheritanceClause,
            memberBlock: MemberBlockSyntax(
                leftBrace: .leftBraceToken(),
                members: memberDeclList,
                rightBrace: .rightBraceToken()
            )
        )

        return DeclSyntax(structDecl)
    }

    
    static func getProperties(from declaration: DeclGroupSyntax, diagnostics: inout [Diagnostic]) -> [ModelConfiguration.Property]
    {
        var properties = [ModelConfiguration.Property]()
        
        let primaryKeyIdProperty = ModelConfiguration.Property(name: primaryKeyFieldName, backingProperty: primaryKeyFieldName, columnName: .init(stringLiteral: primaryKeyFieldName), type: "UUID", positionInPrimaryKey: 0, isVariable: false)
        properties.append(primaryKeyIdProperty)

        for member in declaration.memberBlock.members {
            
            // Only variable declarations are to be processed
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            
            // Static properties are ignored
            guard !varDecl.isStatic else { continue }
            
            // Only a single binding is supported
            guard varDecl.bindings.count == 1 else {
                let diag = Diagnostic(node: varDecl, message: ErrorMessage.unexpectedMultipleBindings)
                diagnostics.append(diag)
                continue
            }
            
            // Only the first variable binding is relevant here
            guard let binding = varDecl.bindings.first else { continue }
            
            // Only identifier patterns are supported (e.g. no tuple patterns)
            guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                let diag = Diagnostic(node: varDecl, message: ErrorMessage.unexpectedBindingPattern)
                diagnostics.append(diag)
                continue
            }
            
            // Variable declarations must have a type
            guard let type = binding.typeAnnotation?.type else {
                let diag = Diagnostic(node: varDecl, message: ErrorMessage.failedToFindType)
                diagnostics.append(diag)
                continue
            }
            
            let name = identifierPattern.identifier.text
            
            var isTransient = false
            var isUnique = false
            var isIndexed = false
            var isRelated = false
            var columnNameExpr: ExprSyntax? = nil
            var defaultValueExpr: ExprSyntax?
            var defaultValuePropertyName: String?
            
            for attribute in varDecl.attributes {
                guard let attrId = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) else { continue }
                switch attrId.name.text {
                case "Transient":
                    isTransient = true
                case "File":
                    // TODO: Implement
                    break
                case "Stored":
                    if case let .attribute(attr) = attribute, case .argumentList(let args) = attr.arguments {
                        for arg in args {
                            let label = arg.label?.text
                            let expr = arg.expression
                            
                            switch label {
                            case "columnName":
                                columnNameExpr = expr
                            case "defaultValue":
                                defaultValueExpr = expr
                                defaultValuePropertyName = "__defaultValue_\(name)"
                            case "isUnique":
                                if let bool = expr.boolLiteral {
                                    isUnique = bool
                                } else {
                                    let diag = Diagnostic(node: arg, message: ErrorMessage.literalExpected)
                                    diagnostics.append(diag)
                                }
                            case "isIndexed":
                                if let bool = expr.boolLiteral {
                                    isIndexed = bool
                                } else {
                                    let diag = Diagnostic(node: arg, message: ErrorMessage.literalExpected)
                                    diagnostics.append(diag)
                                }
                            default:
                                break
                            }
                        }
                    }
                case "Related":
                    isRelated = true
                default:
                    continue
                }
            }
            
            guard !isTransient else {
                continue
            }
            
            let backingProperty: String
            // TODO: Extract this check and name for the backing property
            let isVariable = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
            if isVariable {
                backingProperty = "_backingData.\(name)"
            } else {
                backingProperty = name
            }
            
            let columnName = columnNameExpr ?? "\(raw: name)"
            properties.append(.init(name: name, backingProperty: backingProperty, columnName: columnName, type: type, positionInPrimaryKey: nil, isUnique: isUnique, isIndexed: isIndexed, isRelated: isRelated, isVariable: isVariable, defaultValue: defaultValueExpr, defaultValuePropertyName: defaultValuePropertyName))
            
            
            // Initial values for properties aren't supported in SwiftLite, because they make it impossible to set the value for `let` properties in the initializer (which is what is required when initializing a model from database results)
            // If the binding has an initializer, a diagnostig with a FixIt is shown.
            if let initializer = binding.initializer {
                // TODO: Change FixIt to move the value to a @Default() Macro instead of just deleting the initializer
                let fixIt = FixIt(
                    message: ModelFixItMessage.removeDefaultValue,
                    changes: [
                        FixIt.Change.replace(
                            oldNode: Syntax(initializer),
                            newNode: Syntax(TokenSyntax(stringLiteral: ""))
                        )
                    ]
                )
                
                let diag = Diagnostic(node: varDecl, message: ErrorMessage.unexpectedPropertyDefaultValue, fixIt: fixIt)
                diagnostics.append(diag)
            }
        }
        
        return properties
    }
    
    static func getSchemaTable(tableName: String, properties: [ModelConfiguration.Property]) -> DeclSyntax
    {
        let columnInitializers: String = properties.map { p in
            """
            Columns.\(p.name)
            """
        }.joined(separator: ",\n")
        
        let indexInitializers: String = properties.filter({ $0.isUnique || $0.isIndexed || $0.isRelated }).map { p in
            """
            .init(name: "idx_\(p.columnName)", isUnique: \(p.isUnique), columns: ["\(p.columnName)"])
            """
        }.joined(separator: ",\n")
                
        // TODO: Add indexes from `static let customIndexes`.

        let tableDecl: DeclSyntax =
        """
        static let table = Schema.Table(name: "\(raw: tableName)", columns: [
            \(raw: columnInitializers)
        ], indexes: [
            \(raw: indexInitializers)
        ])
        """
        
        return tableDecl
    }
    
    static func addStaticStoredVariablesForDefaultValues(from: [ModelConfiguration.Property], to: inout [DeclSyntax])
    {
        for property in from
        {
            guard let defaultValuePropertyName = property.defaultValuePropertyName, let defaultValue = property.defaultValue else { continue }
            
            let defaultValueDecl: DeclSyntax =
            """
            private static var \(raw: defaultValuePropertyName): \(property.type) { \(defaultValue) }
            """
            to.append(defaultValueDecl)
        }
    }
    
    static func initializerForNewObject(properties: [ModelConfiguration.Property]) -> InitializerDeclSyntax
    {
        var parameters = [FunctionParameterSyntax]()
        var assignments = [CodeBlockItemSyntax]()
        
        let dbParameterSyntax = FunctionParameterSyntax(
            firstName: "db",
            colon: .colonToken(trailingTrivia: .space),
            type: TypeSyntax("SwiftLite.Database")
        )
        parameters.append(dbParameterSyntax)

        let dbAssignment = CodeBlockItemSyntax(item: .expr("self.db = db"))
        assignments.append(dbAssignment)

        for property in properties {
            guard property.isVariable else { continue }
            if property.name == primaryKeyFieldName {
                // The default UUID primary key is always autogenerated
                let assignment = CodeBlockItemSyntax(item: .expr("self.\(raw: property.name) = .init()"))
                assignments.append(assignment)
            } else {
                let functionParameterSyntax = FunctionParameterSyntax(
                    firstName: .identifier(property.name),
                    colon: .colonToken(trailingTrivia: .space),
                    type: property.type,
                    defaultValue: property.defaultValueInitializer
                )
                parameters.append(functionParameterSyntax)
                
                let assignment = CodeBlockItemSyntax(item: .expr("self.\(raw: property.backingProperty) = \(raw: property.name)"))
                assignments.append(assignment)
            }
        }

        let backingAssignment = CodeBlockItemSyntax(item: .expr("self._backingData = BackingData()"))
        assignments.append(backingAssignment)

        let parameterList = FunctionParameterClauseSyntax { parameters }
        
        let initDecl = InitializerDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            signature: FunctionSignatureSyntax(parameterClause: parameterList),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(assignments))
        )
        
        return initDecl
    }
    
    static func initializerForObjectFromDatabase(properties: [ModelConfiguration.Property], skipRelations: Bool = false, forMainModel: Bool, forBacking: Bool = false) -> InitializerDeclSyntax
    {
        var assignments = [CodeBlockItemSyntax]()
        
        if !forBacking {
            let dbAssignment = CodeBlockItemSyntax(item: .expr("self.db = db"))
            assignments.append(dbAssignment)
        }

        var index = 0
        for property in properties {
            
            if forBacking {
                guard property.isVariable else { continue }
            } else if forMainModel {
                guard !property.isVariable else { continue }
            }
            
            guard !property.isRelated else {
                if !skipRelations {
                    // TODO: Implement fetching of related objects
                    let assignment = CodeBlockItemSyntax(item: .expr("self.\(raw: forMainModel ? property.backingProperty : property.name) = nil"))
                    assignments.append(assignment)
                }
                continue
            }
            let assignment = CodeBlockItemSyntax(item: .expr("self.\(raw: forMainModel ? property.backingProperty : property.name) = try row.getStoredValue(index: \(raw: index))"))
            assignments.append(assignment)
            index += 1
        }
        
        let parameterList = FunctionParameterClauseSyntax {
            FunctionParameterSyntax(
                firstName: "row",
                colon: .colonToken(trailingTrivia: .space),
                type: TypeSyntax("SQLiteQueryResult")
            )
            if !forBacking {
                FunctionParameterSyntax(
                    firstName: "db",
                    colon: .colonToken(trailingTrivia: .space),
                    type: TypeSyntax("SwiftLite.Database")
                )
            }
        }
        
        let initDecl = InitializerDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.public))],
            signature: FunctionSignatureSyntax(parameterClause: parameterList, effectSpecifiers: .throwing),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(assignments))
        )
        
        return initDecl
    }
    
    static func createTableNameFromQualifiedName(of declaration: ClassDeclSyntax?, in context: MacroExpansionContext) -> String?
    {
        guard let declaration else { return nil }
        
        var components: [String] = [declaration.name.text]
        
        for parent in context.lexicalContext {
            guard let named = parent.asProtocol(NamedDeclSyntax.self) else { continue }
            components.insert(named.name.text, at: 0)
        }
        
        return components.joined(separator: ".")
    }
}

