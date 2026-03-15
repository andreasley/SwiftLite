import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct ModelMacro: MemberMacro, ExtensionMacro, MemberAttributeMacro
{
    // MARK: - Diagnostics
    
    enum ModelDiagnostic: String, DiagnosticMessage {
        case requiresFinal
        case requiresClass
        
        var severity: DiagnosticSeverity {
            switch self {
            case .requiresFinal, .requiresClass:
                return .error
            }
        }
        
        var message: String {
            switch self {
            case .requiresFinal:
                return "@Model requires the class to be marked as 'final'"
            case .requiresClass:
                return "@Model can only be applied to classes"
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "SwiftLite", id: rawValue)
        }
    }
    
    private static func validateDeclaration(
        _ declaration: some DeclGroupSyntax,
        node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> ClassDeclSyntax? {
        // Check if it's a class
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            // Try to create helpful Fix-It for struct -> class conversion
            if let structDecl = declaration.as(StructDeclSyntax.self) {
                let diagnostic = Diagnostic(
                    node: node,
                    message: ModelDiagnostic.requiresClass,
                    fixIts: [
                        FixIt(
                            message: MacroExpansionFixItMessage("Change 'struct' to 'final class'"),
                            changes: [
                                .replace(
                                    oldNode: Syntax(structDecl.structKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: structDecl.structKeyword.trailingTrivia))
                                ),
                                .replace(
                                    oldNode: Syntax(structDecl.modifiers),
                                    newNode: Syntax(structDecl.modifiers.appending(
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ))
                                )
                            ]
                        )
                    ]
                )
                context.diagnose(diagnostic)
            } else if let enumDecl = declaration.as(EnumDeclSyntax.self) {
                let diagnostic = Diagnostic(
                    node: node,
                    message: ModelDiagnostic.requiresClass,
                    fixIts: [
                        FixIt(
                            message: MacroExpansionFixItMessage("Change 'enum' to 'final class'"),
                            changes: [
                                .replace(
                                    oldNode: Syntax(enumDecl.enumKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: enumDecl.enumKeyword.trailingTrivia))
                                ),
                                .replace(
                                    oldNode: Syntax(enumDecl.modifiers),
                                    newNode: Syntax(enumDecl.modifiers.appending(
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ))
                                )
                            ]
                        )
                    ]
                )
                context.diagnose(diagnostic)
            } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
                let diagnostic = Diagnostic(
                    node: node,
                    message: ModelDiagnostic.requiresClass,
                    fixIts: [
                        FixIt(
                            message: MacroExpansionFixItMessage("Change 'actor' to 'final class'"),
                            changes: [
                                .replace(
                                    oldNode: Syntax(actorDecl.actorKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: actorDecl.actorKeyword.trailingTrivia))
                                ),
                                .replace(
                                    oldNode: Syntax(actorDecl.modifiers),
                                    newNode: Syntax(actorDecl.modifiers.appending(
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ))
                                )
                            ]
                        )
                    ]
                )
                context.diagnose(diagnostic)
            } else {
                // Generic error for other types
                context.diagnose(Diagnostic(
                    node: node,
                    message: ModelDiagnostic.requiresClass
                ))
            }
            return nil
        }
        
        // Check if class has 'final' modifier
        checkClassIsFinal(classDecl, node: node, in: context)
        
        return classDecl
    }
    
    private static func checkClassIsFinal(
        _ classDecl: ClassDeclSyntax,
        node: AttributeSyntax,
        in context: some MacroExpansionContext
    ) {
        // Check if class has 'final' modifier
        let hasFinal = classDecl.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.final)
        }
        
        guard !hasFinal else { return }
        
        // Create diagnostic with Fix-It
        let diagnostic = Diagnostic(
            node: node,
            message: ModelDiagnostic.requiresFinal,
            fixIts: [
                FixIt(
                    message: MacroExpansionFixItMessage("Add 'final' modifier"),
                    changes: [
                        .replace(
                            oldNode: Syntax(classDecl.modifiers),
                            newNode: Syntax(classDecl.modifiers.appending(
                                DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                            ))
                        )
                    ]
                )
            ]
        )
        
        context.diagnose(diagnostic)
    }

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
        
        // Check if it's a stored property (not a computed property)
        guard let binding = varDecl.bindings.first,
              binding.accessorBlock == nil else {
            // It's a computed property, skip it
            return []
        }
        
        var attributesToAdd = [SwiftSyntax.AttributeSyntax]()
        
        // Check existing attributes
        let existingAttributeNames = varDecl.attributes.compactMap { attribute -> String? in
            guard case let .attribute(attr) = attribute else { return nil }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text
        }
        
        let hasStored = existingAttributeNames.contains("Stored")
        let hasRelated = existingAttributeNames.contains("Related")
        let hasRelatedMany = existingAttributeNames.contains("RelatedMany")
        let hasInverseRelated = existingAttributeNames.contains("InverseRelated")
        let hasInverseRelatedMany = existingAttributeNames.contains("InverseRelatedMany")
        let hasTransient = existingAttributeNames.contains("Transient")
        let hasEditableValue = existingAttributeNames.contains("EditableValue")
        
        // Add @Stored to stored properties that don't have it and aren't relationship properties
        if !hasStored && !hasRelated && !hasRelatedMany && !hasInverseRelated && !hasInverseRelatedMany && !hasTransient {
            attributesToAdd.append(
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("Stored")))
            )
        }
        
        // Add @EditableValue if the property has @Related/@RelatedMany/@Stored and not @Transient or @EditableValue
        if !hasEditableValue && !hasTransient && (hasRelated || hasStored || !attributesToAdd.isEmpty) {
            attributesToAdd.append(
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("EditableValue")))
            )
        }
        
        return attributesToAdd
    }
    
    // MARK: ExtensionMacro
    
    public static func expansion(
        of node: SwiftSyntax.AttributeSyntax,
        attachedTo declaration: some SwiftSyntax.DeclGroupSyntax,
        providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol,
        conformingTo protocols: [SwiftSyntax.TypeSyntax],
        in context: some SwiftSyntaxMacros.MacroExpansionContext
    ) throws -> [SwiftSyntax.ExtensionDeclSyntax]
    {
        guard let classDecl = validateDeclaration(declaration, node: node, in: context) else {
            return []
        }
        
        let className = classDecl.name.text
        
        // Collect property information (same as in MemberMacro)
        let propertyInfo = try collectPropertyInfo(from: classDecl)
        
        // Generate extension with Model conformance
        let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(raw: className): Model") {
            try generateModelProtocolMethods(
                className: className,
                propertyInfo: propertyInfo,
                classDecl: classDecl
            )
            
            try generateSchemaClass(
                className: className,
                propertyInfo: propertyInfo
            )
            
            // Generate RelationshipModelSchema for each @RelatedMany property
            for prop in propertyInfo.relatedMany {
                try generateRelationshipModelSchema(
                    className: className,
                    property: prop
                )
            }
            
            try generateDefaultValuesStruct(propertyInfo: propertyInfo)
            
            try generateFallbackValuesStruct(propertyInfo: propertyInfo)
                        
            try generateQueryProxyStruct(
                className: className,
                propertyInfo: propertyInfo
            )
            
            try generateSnapshotStruct(
                className: className,
                propertyInfo: propertyInfo,
                classDecl: classDecl
            )
        }
        
        return [extensionDecl]
    }
    
    private static func collectPropertyInfo(from classDecl: ClassDeclSyntax) throws -> PropertyInfo {
        var storedProperties: [(name: String, type: String, hasDefault: Bool, defaultValue: String?)] = []
        var relatedProperties: [(name: String, type: String, isOptional: Bool, onDelete: String?)] = []
        var relatedManyProperties: [(name: String, elementType: String, schemaType: String, onDelete: String?)] = []
        var inverseRelatedProperties: [(name: String, type: String, referencingField: String)] = []
        var inverseRelatedManyProperties: [(name: String, type: String, keyPath: String)] = []
        var computedProperties: [(name: String, body: String)] = []
        
        for member in classDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            
            let propertyName = identifier.identifier.text
            let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription ?? ""
            
            // Check if it's a computed property
            if let accessor = binding.accessorBlock {
                if let codeBlock = accessor.accessors.as(CodeBlockItemListSyntax.self) {
                    let body = codeBlock.trimmedDescription
                    computedProperties.append((name: propertyName, body: body))
                }
                continue
            }
            
            // Parse attributes
            var isStored = false
            var isRelated = false
            var isRelatedMany = false
            var isInverseRelated = false
            var isInverseRelatedMany = false
            var defaultValue: String? = nil
            var elementType: String? = nil
            var onDelete: String? = nil
            var referencingField: String? = nil
            var keyPath: String? = nil
            
            for attribute in varDecl.attributes {
                guard case let .attribute(attr) = attribute,
                      let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                    continue
                }
                
                if attrName == "Stored" {
                    isStored = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            if argument.label?.text == "defaultValue" {
                                defaultValue = argument.expression.trimmedDescription
                            }
                        }
                    }
                } else if attrName == "Related" {
                    isRelated = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            if argument.label?.text == "onDelete" {
                                onDelete = argument.expression.trimmedDescription
                            }
                        }
                    }
                } else if attrName == "RelatedMany" {
                    isRelatedMany = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for (index, argument) in arguments.enumerated() {
                            if index == 0 {
                                let exprText = argument.expression.trimmedDescription
                                if exprText.hasSuffix(".self") {
                                    elementType = String(exprText.dropLast(5))
                                }
                            } else if argument.label?.text == "onDelete" {
                                onDelete = argument.expression.trimmedDescription
                            }
                        }
                    }
                } else if attrName == "InverseRelated" {
                    isInverseRelated = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            // The first argument is a key path like \Car.engine
                            let keyPathText = argument.expression.trimmedDescription
                            // Extract the field name from the keypath (e.g., "engine" from "\Car.engine")
                            if let dotIndex = keyPathText.lastIndex(of: ".") {
                                referencingField = String(keyPathText[keyPathText.index(after: dotIndex)...])
                            }
                        }
                    }
                } else if attrName == "InverseRelatedMany" {
                    isInverseRelatedMany = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            // The first argument is a key path like \Car.passengers
                            keyPath = argument.expression.trimmedDescription
                        }
                    }
                }
            }
            
            if isStored {
                storedProperties.append((name: propertyName, type: typeAnnotation, hasDefault: defaultValue != nil, defaultValue: defaultValue))
            } else if isRelated {
                let isOptional = typeAnnotation.hasSuffix("?")
                relatedProperties.append((name: propertyName, type: typeAnnotation, isOptional: isOptional, onDelete: onDelete))
            } else if isRelatedMany, let element = elementType {
                let schemaName = "\(propertyName.prefix(1).uppercased())\(propertyName.dropFirst())RelationSchema"
                relatedManyProperties.append((name: propertyName, elementType: element, schemaType: schemaName, onDelete: onDelete))
            } else if isInverseRelated, let field = referencingField {
                inverseRelatedProperties.append((name: propertyName, type: typeAnnotation, referencingField: field))
            } else if isInverseRelatedMany, let kp = keyPath {
                inverseRelatedManyProperties.append((name: propertyName, type: typeAnnotation, keyPath: kp))
            }
        }
        
        return PropertyInfo(
            stored: storedProperties,
            related: relatedProperties,
            relatedMany: relatedManyProperties,
            inverseRelated: inverseRelatedProperties,
            inverseRelatedMany: inverseRelatedManyProperties,
            computed: computedProperties
        )
    }
    
    private struct PropertyInfo {
        let stored: [(name: String, type: String, hasDefault: Bool, defaultValue: String?)]
        let related: [(name: String, type: String, isOptional: Bool, onDelete: String?)]
        let relatedMany: [(name: String, elementType: String, schemaType: String, onDelete: String?)]
        let inverseRelated: [(name: String, type: String, referencingField: String)]
        let inverseRelatedMany: [(name: String, type: String, keyPath: String)]
        let computed: [(name: String, body: String)]
    }
    
    // MARK: MemberMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax]
    {
        guard let classDecl = validateDeclaration(declaration, node: node, in: context) else {
            return []
        }
        
        let className = classDecl.name.text
        let propertyInfo = try collectPropertyInfo(from: classDecl)
        
        var members: [DeclSyntax] = []
        
        // Generate metadata and editableData properties
        members.append(
            """
            let _metadata: ModelMetadata
            """
        )
        
        if !propertyInfo.stored.isEmpty || !propertyInfo.related.isEmpty || !propertyInfo.relatedMany.isEmpty || !propertyInfo.inverseRelated.isEmpty || !propertyInfo.inverseRelatedMany.isEmpty {
            members.append(
                """
                let _editableData: EditableData
                """
            )
        }
        
        // Generate id property
        members.append(
            """
            let id: UUID
            """
        )
                        
        // Generate first initializer (for creating new objects)
        members.append(generateCreateInitializer(
            className: className,
            propertyInfo: propertyInfo
        ))
        
        // Generate second initializer (for loading from database)
        members.append(generateRowInitializer(
            className: className,
            propertyInfo: propertyInfo
        ))
        
        members.append(try generateEditableDataClass(propertyInfo: propertyInfo, className: className))
        
        return members
    }
        
    private static func generateCreateInitializer(
        className: String,
        propertyInfo: PropertyInfo
    ) -> DeclSyntax {
        // Build parameter list
        var parameters: [String] = ["db: Database"]
        
        // Add stored properties with defaults
        for prop in propertyInfo.stored {
            if prop.hasDefault, let defaultVal = prop.defaultValue {
                parameters.append("\(prop.name): \(prop.type) = DefaultValues.\(prop.name)")
            }
        }
        
        // Add related properties (required ones first, optional ones with defaults)
        for prop in propertyInfo.related {
            if prop.isOptional {
                parameters.append("\(prop.name): \(prop.type) = DefaultValues.\(prop.name)")
            } else {
                parameters.append("\(prop.name): \(prop.type)")
            }
        }
        
        // Build the initializer body
        var bodyLines: [String] = [
            "let id = UUID()"
        ]
        
        // Initialize many-to-many relationships
        for prop in propertyInfo.relatedMany {
            bodyLines.append("let \(prop.name) = ManyToMany<\(prop.schemaType)>(db: db, parentId: id)")
        }
        
        // Initialize inverse relationships
        for prop in propertyInfo.inverseRelated {
            let relatedType = extractRelatedType(from: prop.type)
            bodyLines.append("let \(prop.name) = Inverse<\(relatedType), \(className)>(db: db, objectId: id, referencingField: \"\(prop.referencingField)\")")
        }
        
        // Initialize inverse many-to-many relationships
        for prop in propertyInfo.inverseRelatedMany {
            let transformedKeyPath = transformKeyPath(prop.keyPath)
            bodyLines.append("let \(prop.name) = InverseManyToMany(keyPath: \(transformedKeyPath), db: db, elementId: id)")
        }
        
        bodyLines.append("")
        bodyLines.append("self._metadata = Metadata(db: db, table: Schema.table.name, id: id, isNew: true)")
        
        // Build EditableData initialization
        if !propertyInfo.stored.isEmpty || !propertyInfo.related.isEmpty || !propertyInfo.relatedMany.isEmpty || !propertyInfo.inverseRelated.isEmpty || !propertyInfo.inverseRelatedMany.isEmpty {
            var editableParams: [String] = []
            for prop in propertyInfo.stored {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.related {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.relatedMany {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.inverseRelated {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.inverseRelatedMany {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            bodyLines.append("self._editableData = EditableData(\(editableParams.joined(separator: ", ")))")
        }
        
        bodyLines.append("")
        bodyLines.append("self.id = id")
        
        // Assign stored properties to self
        for prop in propertyInfo.stored {
            bodyLines.append("self.\(prop.name) = \(prop.name)")
        }
        
        bodyLines.append("")
        
        // Read-only data needs to be added to the changelog, so it will be committed to the database when this object is saved for the first time
        bodyLines.append("self._metadata.logValueChange(field: \"id\", value: id)")

        for prop in propertyInfo.stored {
            bodyLines.append("self._metadata.logValueChange(field: \"\(prop.name)\", value: \(prop.name))")
        }
        
        for prop in propertyInfo.related {
            bodyLines.append("self._metadata.logValueChange(field: \"\(prop.name)\", value: \(prop.name))")
        }
        
        let paramString = parameters.joined(separator: ", ")
        let bodyString = bodyLines.joined(separator: "\n        ")
        
        return """
        init(\(raw: paramString))
        {
            \(raw: bodyString)
        }
        """
    }
    
    private static func generateRowInitializer(
        className: String,
        propertyInfo: PropertyInfo
    ) -> DeclSyntax {
        var bodyLines: [String] = [
            "let id: UUID = try row.get(\"id\")"
        ]
        
        // Extract stored properties from row
        for prop in propertyInfo.stored {
            if prop.hasDefault {
                bodyLines.append("let \(prop.name): \(prop.type) = try row.get(\"\(prop.name)\", fallback: FallbackValues.\(prop.name))")
            } else {
                bodyLines.append("let \(prop.name): \(prop.type) = try row.get(\"\(prop.name)\")")
            }
        }
        
        // Extract related properties from row
        for prop in propertyInfo.related {
            bodyLines.append("let \(prop.name): \(prop.type) = try await row.get(\"\(prop.name)\")")
        }
        
        // Extract many-to-many relationships from row
        for prop in propertyInfo.relatedMany {
            bodyLines.append("let \(prop.name): ManyToMany<\(prop.schemaType)> = try await row.get(parentId: id)")
        }
        
        // Extract inverse relationships from row
        for prop in propertyInfo.inverseRelated {
            let relatedType = extractRelatedType(from: prop.type)
            bodyLines.append("let \(prop.name): Inverse<\(relatedType), \(className)> = try await row.get(objectId: id, referencingField: \"\(prop.referencingField)\")")
        }
        
        // Extract inverse many-to-many relationships from row
        for prop in propertyInfo.inverseRelatedMany {
            let relatedType = extractRelatedType(from: prop.type)
            let transformedKeyPath = transformKeyPath(prop.keyPath)
            bodyLines.append("let \(prop.name): any AnyInverseManyToMany<\(relatedType)> = try await row.get(inverse: \(transformedKeyPath), db: db, elementId: id)")
        }
        
        bodyLines.append("")
        bodyLines.append("self._metadata = Metadata(db: db, table: Schema.table.name, id: id, isNew: false)")
        
        // Build EditableData initialization
        if !propertyInfo.stored.isEmpty || !propertyInfo.related.isEmpty || !propertyInfo.relatedMany.isEmpty || !propertyInfo.inverseRelated.isEmpty || !propertyInfo.inverseRelatedMany.isEmpty {
            var editableParams: [String] = []
            for prop in propertyInfo.stored {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.related {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.relatedMany {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.inverseRelated {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.inverseRelatedMany {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            bodyLines.append("self._editableData = EditableData(\(editableParams.joined(separator: ", ")))")
        }
        
        bodyLines.append("")
        bodyLines.append("self.id = id")
        
        // Assign stored properties to self
        for prop in propertyInfo.stored {
            bodyLines.append("self.\(prop.name) = \(prop.name)")
        }
        
        let bodyString = bodyLines.joined(separator: "\n        ")
        
        return """
        init(db: Database, row: Database.Row) async throws
        {
            \(raw: bodyString)
        }
        """
    }
    
    // MARK: - Extension Generation Helpers
    
    private static func generateModelProtocolMethods(
        className: String,
        propertyInfo: PropertyInfo,
        classDecl: ClassDeclSyntax
    ) throws -> DeclSyntax {
        var methods = [String]()
        
        // _beginAutoupdating
        var autoupdatingCalls = ["_metadata._beginAutoupdating(model: self)"]
        for prop in propertyInfo.related {
            if prop.isOptional {
                autoupdatingCalls.append("\(prop.name)?._beginAutoupdating()")
            } else {
                autoupdatingCalls.append("\(prop.name)._beginAutoupdating()")
            }
        }
        for prop in propertyInfo.relatedMany {
            autoupdatingCalls.append("_editableData.\(prop.name)._beginAutoupdating()")
        }
        for prop in propertyInfo.inverseRelated {
            autoupdatingCalls.append("_editableData.\(prop.name)._beginAutoupdating()")
        }
        for prop in propertyInfo.inverseRelatedMany {
            autoupdatingCalls.append("_editableData.\(prop.name)._beginAutoupdating()")
        }
        
        methods.append("""
        @MainActor
        func _beginAutoupdating()
        {
            \(autoupdatingCalls.joined(separator: "\n    "))
        }
        """)
        
        // _hasPendingChanges
        var hasPendingChecks = ["_metadata._hasPendingChanges"]
        for prop in propertyInfo.related {
            if prop.isOptional {
                hasPendingChecks.append("\(prop.name)?._hasPendingChanges")
            } else {
                hasPendingChecks.append("\(prop.name)._hasPendingChanges")
            }
        }
        for prop in propertyInfo.relatedMany {
            hasPendingChecks.append("_editableData.\(prop.name)._hasPendingChanges")
        }
        for prop in propertyInfo.inverseRelated {
            hasPendingChecks.append("_editableData.\(prop.name)._hasPendingChanges")
        }
        for prop in propertyInfo.inverseRelatedMany {
            hasPendingChecks.append("_editableData.\(prop.name)._hasPendingChanges")
        }
        
        methods.append("""
        var _hasPendingChanges: Bool {
            let hasChanges = [
                \(hasPendingChecks.joined(separator: ",\n        "))
            ]
            .contains(true)
            return hasChanges
        }
        """)
        
        // _beginSaving
        var beginSavingCalls = ["try _metadata._beginSaving(transaction: transaction, changeset: changeset)"]
        for prop in propertyInfo.related {
            if prop.isOptional {
                beginSavingCalls.append("try \(prop.name)?._beginSaving(transaction: transaction, changeset: changeset)")
            } else {
                beginSavingCalls.append("try \(prop.name)._beginSaving(transaction: transaction, changeset: changeset)")
            }
        }
        for prop in propertyInfo.relatedMany {
            beginSavingCalls.append("try _editableData.\(prop.name)._beginSaving(transaction: transaction, changeset: changeset)")
        }
        for prop in propertyInfo.inverseRelated {
            beginSavingCalls.append("try _editableData.\(prop.name)._beginSaving(transaction: transaction, changeset: changeset)")
        }
        for prop in propertyInfo.inverseRelatedMany {
            beginSavingCalls.append("try _editableData.\(prop.name)._beginSaving(transaction: transaction, changeset: changeset)")
        }
        
        methods.append("""
        func _beginSaving(transaction: DatabaseTask.WriteTransaction, changeset: Changeset) throws
        {
            \(beginSavingCalls.joined(separator: "\n    "))
        }
        """)
        
        // _endSaving
        var endSavingCalls = [
            "_metadata._endSaving(success: success, transaction: transaction)"
        ]
        for prop in propertyInfo.related {
            if prop.isOptional {
                endSavingCalls.append("\(prop.name)?._endSaving(success: success, transaction: transaction)")
            } else {
                endSavingCalls.append("\(prop.name)._endSaving(success: success, transaction: transaction)")
            }
        }
        for prop in propertyInfo.relatedMany {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transaction: transaction)")
        }
        for prop in propertyInfo.inverseRelated {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transaction: transaction)")
        }
        for prop in propertyInfo.inverseRelatedMany {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transaction: transaction)")
        }
        
        methods.append("""
        func _endSaving(success: Bool, transaction: DatabaseTask.WriteTransaction)
        {
            let wasNew = _metadata.objectStatus == .new
            \(endSavingCalls.joined(separator: "\n    "))
            if wasNew {
                _beginAutoupdatingIfOnMainActor()
            }
        }
        """)
        
        // _update
        var updateCalls = [String]()
        for prop in propertyInfo.stored {
            updateCalls.append("try await update(field: \"\(prop.name)\", writableKeyPath: \\._editableData.\(prop.name), newValue: updatedFields[\"\(prop.name)\"])")
        }
        for prop in propertyInfo.related {
            updateCalls.append("try await update(field: \"\(prop.name)\", writableKeyPath: \\._editableData.\(prop.name), newValue: updatedFields[\"\(prop.name)\"])")
        }
        
        methods.append("""
        func _update(with changes: ChangedObject) async throws
        {
            _metadata._update(with: changes)
        """)
        
           if !updateCalls.isEmpty {
                methods.append("""
                if let updatedFields = changes.updatedFields {
                    \(updateCalls.joined(separator: "\n"))
                }
                """)
           }

        methods.append("}\n")
        
        // _cascadeDeletion
        var cascadeCalls = ["_metadata._cascadeDeletion()"]
        for prop in propertyInfo.related {
            if prop.onDelete == ".cascade" {
                if prop.isOptional {
                    cascadeCalls.append("\(prop.name)?._cascadeDeletion()")
                } else {
                    cascadeCalls.append("\(prop.name)._cascadeDeletion()")
                }
            }
        }
        for prop in propertyInfo.relatedMany {
            if prop.onDelete == ".cascade" {
                cascadeCalls.append("_editableData.\(prop.name)._cascadeDeletion()")
            }
        }
        
        methods.append("""
        func _cascadeDeletion()
        {
            \(cascadeCalls.joined(separator: "\n    "))
        }
        """)
        
        return """
        \(raw: methods.joined(separator: "\n\n"))
        """
    }
    
    private static func generateSchemaClass(
        className: String,
        propertyInfo: PropertyInfo
    ) throws -> DeclSyntax {
        var relatedTypes = [String]()
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            relatedTypes.append("\(baseType).Model.Schema.self")
        }
        for prop in propertyInfo.relatedMany {
            relatedTypes.append("\(prop.elementType).Model.Schema.self")
            relatedTypes.append("\(prop.schemaType).self")
        }
        
        var columns = ["Columns.id"]
        var columnDefs = ["static let id = RequiredSchema.Column(name: \"id\", type: UUID.self)"]
        var indexes = [String]()
        var foreignKeys = [String]()
        
        for prop in propertyInfo.stored {
            columns.append("Columns.\(prop.name)")
            columnDefs.append("static let \(prop.name) = RequiredSchema.Column(name: \"\(prop.name)\", type: \(prop.type).self)")
        }
        
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            columns.append("Columns.\(prop.name)")
            columnDefs.append("static let \(prop.name) = RequiredSchema.Column(name: \"\(prop.name)\", type: \(baseType).self)")
            indexes.append(".init(name: \"idx_\(prop.name)\", isUnique: false, columns: [Columns.\(prop.name)])")
            foreignKeys.append(".init(column: \"\(prop.name)\", referencedTable: \"\(baseType)\")")
        }
        
        return """
        final class Schema: ModelSchema
        {
            typealias Model = \(raw: className)
            
            static let related: [any ModelSchema.Type] = [\(raw: relatedTypes.joined(separator: ", "))]
            
            struct Columns
            {
                \(raw: columnDefs.joined(separator: "\n        "))
            }
        
            static let table = RequiredSchema.Table(name: "\(raw: className)", columns: [
                \(raw: columns.joined(separator: ",\n        "))
            ], indexes: [
                \(raw: indexes.joined(separator: ",\n        "))
            ], foreignKeys: [
                \(raw: foreignKeys.joined(separator: ",\n        "))
            ])
        }
        """
    }
    
    private static func generateRelationshipModelSchema(
        className: String,
        property: (name: String, elementType: String, schemaType: String, onDelete: String?)
    ) throws -> DeclSyntax {
        let deletionPolicy = property.onDelete ?? ".nullify"
        let tableName = "\(className)_\(property.name)__\(property.elementType)"
        
        return """
        nonisolated final class \(raw: property.schemaType): RelationshipModelSchema
        {
            typealias Parent = \(raw: className)
            typealias Element = \(raw: property.elementType)
            typealias Model = ManyToMany<\(raw: property.schemaType)>.JunctionModel

            static let deletionPolicy: DeletionPolicy = \(raw: deletionPolicy)
            
            static let table = RelationshipModelSchemaDefaults.getTable(name: "\(raw: tableName)", parentTable: Parent.Schema.table.name, elementTable: Element.Schema.table.name)
        }
        """
    }
    
    private static func generateDefaultValuesStruct(propertyInfo: PropertyInfo) throws -> DeclSyntax {
        var defaultVars = [String]()
        
        for prop in propertyInfo.stored where prop.hasDefault {
            if let defaultValue = prop.defaultValue {
                defaultVars.append("static var \(prop.name): \(prop.type) { \(defaultValue) }")
            }
        }
        
        for prop in propertyInfo.related where prop.isOptional {
            defaultVars.append("static var \(prop.name): \(prop.type) { nil }")
        }
        
        return """
        struct DefaultValues
        {
            \(raw: defaultVars.joined(separator: "\n    "))
        }
        """
    }
    
    private static func generateFallbackValuesStruct(propertyInfo: PropertyInfo) throws -> DeclSyntax {
        var fallbackVars = [String]()
        
        for prop in propertyInfo.stored where prop.hasDefault {
            // Generate appropriate fallback based on type
            let fallback: String
            if prop.type == "String" {
                fallback = "\"\""
            } else if prop.type == "Int" || prop.type == "Double" || prop.type == "Float" {
                fallback = "0"
            } else if prop.type == "Bool" {
                fallback = "false"
            } else {
                // For complex types, use default constructor
                fallback = "\(prop.type)()"
            }
            fallbackVars.append("static var \(prop.name): \(prop.type) { \(fallback) }")
        }
        
        guard !fallbackVars.isEmpty else {
            return """
            struct FallbackValues {}
            """
        }
        
        return """
        struct FallbackValues
        {
            \(raw: fallbackVars.joined(separator: "\n    "))
        }
        """
    }
    
    private static func generateEditableDataClass(propertyInfo: PropertyInfo, className: String) throws -> DeclSyntax {
        var properties = [String]()
        var initParams = [String]()
        var initAssignments = [String]()
        
        for prop in propertyInfo.stored {
            properties.append("var \(prop.name): \(prop.type)")
            initParams.append("\(prop.name): \(prop.type)")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        for prop in propertyInfo.related {
            properties.append("var \(prop.name): \(prop.type)")
            initParams.append("\(prop.name): \(prop.type)")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        for prop in propertyInfo.relatedMany {
            properties.append("var \(prop.name): ManyToMany<\(prop.schemaType)>")
            initParams.append("\(prop.name): ManyToMany<\(prop.schemaType)>")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        for prop in propertyInfo.inverseRelated {
            // Extract the related type from RelatedCollection<Type.Snapshot>
            let relatedType = extractRelatedType(from: prop.type)
            properties.append("let \(prop.name): Inverse<\(relatedType), \(className)>")
            initParams.append("\(prop.name): Inverse<\(relatedType), \(className)>")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        for prop in propertyInfo.inverseRelatedMany {
            // Extract the related type from RelatedCollection<Type.Snapshot> and get base type
            let relatedType = extractRelatedType(from: prop.type)
            properties.append("var \(prop.name): any AnyInverseManyToMany<\(relatedType)>")
            initParams.append("\(prop.name): any AnyInverseManyToMany<\(relatedType)>")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        return """
        @Observable internal nonisolated final class EditableData
        {
            \(raw: properties.joined(separator: "\n    "))
        
            fileprivate init(\(raw: initParams.joined(separator: ", ")))
            {
                \(raw: initAssignments.joined(separator: "\n        "))
            }
        }
        """
    }
    
    // Helper function to extract type from RelatedCollection<Type>
    private static func extractRelatedType(from typeAnnotation: String) -> String {
        // Extract Type from RelatedCollection<Type>
        if let start = typeAnnotation.firstIndex(of: "<"),
           let end = typeAnnotation.lastIndex(of: ">") {
            return String(typeAnnotation[typeAnnotation.index(after: start)..<end])
        }
        return typeAnnotation
    }
    
    // Helper function to transform keyPath from \Model.property to \Model._editableData.property
    private static func transformKeyPath(_ keyPath: String) -> String {
        // keyPath is something like \SomeModel.someProperty
        // We need to transform it to \SomeModel._editableData.someProperty
        
        // Find the first dot that separates the model name from the property
        if let dotIndex = keyPath.firstIndex(of: ".") {
            let beforeDot = keyPath[..<dotIndex]  // \SomeModel
            let afterDot = keyPath[keyPath.index(after: dotIndex)...]  // someProperty
            return "\(beforeDot)._editableData.\(afterDot)"
        }
        
        // If no dot found, return as-is (shouldn't happen in normal cases)
        return keyPath
    }
    
    private static func generateQueryProxyStruct(
        className: String,
        propertyInfo: PropertyInfo
    ) throws -> DeclSyntax {
        var properties = ["let id: UUID"]
        var cases = ["case \\.id: \"id\""]
        
        for prop in propertyInfo.stored {
            properties.append("let \(prop.name): \(prop.type)")
            cases.append("case \\.\(prop.name): \"\(prop.name)\"")
        }
        
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            properties.append("let \(prop.name): \(prop.type)")
            cases.append("case \\.\(prop.name): \"\(prop.name)\"")
        }
        
        return """
        nonisolated struct QueryProxy: WithNamedKeyPaths
        {
            \(raw: properties.joined(separator: "\n    "))
        
            static func nameForKeyPath(keyPath: PartialKeyPath<Self>) -> String
            {
                switch keyPath {
                \(raw: cases.joined(separator: "\n        "))
                default: fatalError("Failed to find name for KeyPath")
                }
            }
        }
        """
    }
    
    private static func generateSnapshotStruct(
        className: String,
        propertyInfo: PropertyInfo,
        classDecl: ClassDeclSyntax
    ) throws -> DeclSyntax {
        var computedProps = [String]()
        for prop in propertyInfo.computed {
            computedProps.append("""
            var \(prop.name): String {
                \(prop.body)
            }
            """)
        }
        
        var storedProps = [
            "let _metadata: SnapshotMetadata<Self>",
            "",
            "let id: UUID"
        ]
        
        var rowExtractions = ["let id: UUID = try row.get(\"id\")", "", "self._metadata = SnapshotMetadata<Self>(id: id, db: db)", "", "self.id = id"]
        
        for prop in propertyInfo.stored {
            storedProps.append("let \(prop.name): \(prop.type)")
            rowExtractions.append("self.\(prop.name) = try row.get(\"\(prop.name)\")")
        }
        
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "").replacingOccurrences(of: ".Snapshot", with: "")
            if prop.isOptional {
                storedProps.append("")
                storedProps.append("let _\(prop.name): DirectRelationReference<\(baseType)>?")
                storedProps.append("var \(prop.name): \(baseType).Snapshot? {")
                storedProps.append("    get async throws {")
                storedProps.append("        guard let _\(prop.name) else { return nil }")
                storedProps.append("        return try await _metadata.db.resolve(_\(prop.name))")
                storedProps.append("    }")
                storedProps.append("}")
                rowExtractions.append("self._\(prop.name) = try row.get(\"\(prop.name)\")")
            } else {
                storedProps.append("")
                storedProps.append("let _\(prop.name): DirectRelationReference<\(baseType)>")
                storedProps.append("var \(prop.name): \(baseType).Snapshot {")
                storedProps.append("    get async throws {")
                storedProps.append("        try await _metadata.db.resolve(_\(prop.name))")
                storedProps.append("    }")
                storedProps.append("}")
                rowExtractions.append("self._\(prop.name) = try row.get(\"\(prop.name)\")")
            }
        }
        
        return """
        nonisolated struct Snapshot: ModelSnapshot
        {
            typealias Model = \(raw: className)
            
            \(raw: computedProps.joined(separator: "\n    "))
            
            \(raw: storedProps.joined(separator: "\n    "))
        
            init(db: Database, row: Database.Row) async throws
            {
                \(raw: rowExtractions.joined(separator: "\n        "))
            }
        }
        """
    }
}

