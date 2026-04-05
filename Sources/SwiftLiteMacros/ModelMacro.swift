import Foundation
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
        case propertyNeedsAnnotation
        
        var severity: DiagnosticSeverity {
            switch self {
            case .requiresFinal, .requiresClass, .propertyNeedsAnnotation:
                return .error
            }
        }
        
        var message: String {
            switch self {
            case .requiresFinal:
                return "@Model requires the class to be marked as 'final'"
            case .requiresClass:
                return "@Model can only be applied to classes"
            case .propertyNeedsAnnotation:
                return "Property in @Model class must be annotated with @Stored, @Transient, or a relationship attribute"
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "SwiftLite", id: rawValue)
        }
    }
    
    private static func isPublic(_ classDecl: ClassDeclSyntax) -> Bool {
        classDecl.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.public)
        }
    }
    
    private static func hasLifecycleFunctions(_ node: AttributeSyntax) -> Bool {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return false
        }
        
        for argument in arguments {
            if argument.label?.text == "withLifecycleFunctions" {
                let exprText = argument.expression.trimmedDescription
                return exprText == "true"
            }
        }
        
        return false
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
                                FixIt.Change.replace(
                                    oldNode: Syntax(structDecl.structKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: structDecl.structKeyword.trailingTrivia))
                                ),
                                FixIt.Change.replace(
                                    oldNode: Syntax(structDecl.modifiers),
                                    newNode: Syntax(structDecl.modifiers + [
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ])
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
                                FixIt.Change.replace(
                                    oldNode: Syntax(enumDecl.enumKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: enumDecl.enumKeyword.trailingTrivia))
                                ),
                                FixIt.Change.replace(
                                    oldNode: Syntax(enumDecl.modifiers),
                                    newNode: Syntax(enumDecl.modifiers + [
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ])
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
                                FixIt.Change.replace(
                                    oldNode: Syntax(actorDecl.actorKeyword),
                                    newNode: Syntax(TokenSyntax.keyword(.class, trailingTrivia: actorDecl.actorKeyword.trailingTrivia))
                                ),
                                FixIt.Change.replace(
                                    oldNode: Syntax(actorDecl.modifiers),
                                    newNode: Syntax(actorDecl.modifiers + [
                                        DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                                    ])
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
                        FixIt.Change.replace(
                            oldNode: Syntax(classDecl.modifiers),
                            newNode: Syntax(classDecl.modifiers + [
                                DeclModifierSyntax(name: .keyword(.final), trailingTrivia: .space)
                            ])
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
        
        // If the property doesn't have any of the required annotations, emit a warning with Fix-Its
        if !hasStored && !hasRelated && !hasRelatedMany && !hasInverseRelated && !hasInverseRelatedMany && !hasTransient {
            // Create Fix-Its for adding @Stored or @Transient
            let storedFixIt = FixIt(
                message: MacroExpansionFixItMessage("Add @Stored attribute"),
                changes: [
                    FixIt.Change.replace(
                        oldNode: Syntax(varDecl.attributes),
                        newNode: Syntax(varDecl.attributes + [
                            .attribute(AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("Stored"))))
                        ])
                    )
                ]
            )
            
            let transientFixIt = FixIt(
                message: MacroExpansionFixItMessage("Add @Transient attribute"),
                changes: [
                    FixIt.Change.replace(
                        oldNode: Syntax(varDecl.attributes),
                        newNode: Syntax(varDecl.attributes + [
                            .attribute(AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("Transient"))))
                        ])
                    )
                ]
            )
            
            let diagnostic = Diagnostic(
                node: Syntax(varDecl),
                message: ModelDiagnostic.propertyNeedsAnnotation,
                fixIts: [storedFixIt, transientFixIt]
            )
            
            context.diagnose(diagnostic)
        }
        
        // Add @EditableValue if the property has @Related/@RelatedMany/@Stored and not @Transient or @EditableValue
        var attributesToAdd = [SwiftSyntax.AttributeSyntax]()
        if !hasEditableValue && !hasTransient && (hasRelated || hasStored) {
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
        let isPublic = isPublic(classDecl)
        let withLifecycleFunctions = hasLifecycleFunctions(node)
        
        // Collect property information (same as in MemberMacro)
        let propertyInfo = try collectPropertyInfo(from: classDecl)
        
        // Generate extension with Model conformance (and optionally WithModelLifecycleFunctions)
        let conformanceList = withLifecycleFunctions ? "Model, WithModelLifecycleFunctions" : "Model"
        let extensionDecl = try ExtensionDeclSyntax("nonisolated extension \(raw: className): \(raw: conformanceList)") {
            
            // This is rquired to prevent circular references when compiling Schemas
            """
            static let _tableName = "\(raw: className)"
            
            """

            try generateModelProtocolMethods(
                className: className,
                propertyInfo: propertyInfo,
                classDecl: classDecl,
                isPublic: isPublic,
                withLifecycleFunctions: withLifecycleFunctions
            )
            
            try generateSchemaClass(
                className: className,
                propertyInfo: propertyInfo,
                isPublic: isPublic
            )
            
            // Generate RelationshipModelSchema for each @RelatedMany property
            for prop in propertyInfo.relatedMany {
                try generateRelationshipModelSchema(
                    className: className,
                    property: prop
                )
            }
            
            try generateDefaultValuesStruct(propertyInfo: propertyInfo, isPublic: isPublic)
            
            try generateFallbackValuesStruct(propertyInfo: propertyInfo, isPublic: isPublic)
                        
            try generateQueryProxyStruct(
                className: className,
                propertyInfo: propertyInfo,
                isPublic: isPublic
            )
            
            try generateSnapshotStruct(
                className: className,
                propertyInfo: propertyInfo,
                classDecl: classDecl,
                isPublic: isPublic
            )
        }
        
        return [extensionDecl]
    }
    
    private static func collectPropertyInfo(from classDecl: ClassDeclSyntax) throws -> PropertyInfo {
        var storedProperties: [(name: String, type: String, isOptional: Bool, hasDefault: Bool, defaultValue: String?, fallbackValue: String?, isIndexed: Bool, isUnique: Bool, isLet: Bool)] = []
        var relatedProperties: [(name: String, type: String, isOptional: Bool, hasDefault: Bool, defaultValue: String?, fallbackValue: String?, isUnique: Bool, onDelete: String?, isLet: Bool, isSnapshotPrefetched: Bool)] = []
        var relatedManyProperties: [(name: String, elementType: String, collectionElementType: String, schemaType: String, onDelete: String?, isSnapshotPrefetched: Bool)] = []
        var inverseRelatedProperties: [(name: String, type: String, referencingField: String)] = []
        var inverseRelatedManyProperties: [(name: String, type: String, keyPath: String)] = []
        var computedProperties: [(name: String, type: String, body: String)] = []
        
        for member in classDecl.memberBlock.members {
            // Check if it's a function with @SnapshotCompatible
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                let hasSnapshotCompatible = funcDecl.attributes.contains { attribute in
                    guard case let .attribute(attr) = attribute,
                          let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                        return false
                    }
                    return attrName == "SnapshotCompatible"
                }
                
                if hasSnapshotCompatible {
                    let functionName = funcDecl.name.text
                    let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"
                    
                    // Get the function signature (parameters)
                    let parameters = funcDecl.signature.parameterClause.parameters
                    let paramList = parameters.map { param -> String in
                        let firstName = param.firstName.text
                        let secondName = param.secondName?.text
                        let paramType = param.type.trimmedDescription
                        
                        if let secondName = secondName {
                            return "\(firstName) \(secondName): \(paramType)"
                        } else {
                            return "\(firstName): \(paramType)"
                        }
                    }.joined(separator: ", ")
                    
                    // Get function modifiers (nonisolated, nonsending, etc.)
                    // Filter out @SnapshotCompatible and any other attributes
                    let modifiers = funcDecl.modifiers.map { modifier in
                        modifier.trimmedDescription
                    }.joined(separator: " ")
                    let modifierString = modifiers.isEmpty ? "" : modifiers + " "
                    
                    // Get effect specifiers (async, throws, etc.)
                    var effectSpecifiers = [String]()
                    if let asyncKeyword = funcDecl.signature.effectSpecifiers?.asyncSpecifier {
                        effectSpecifiers.append(asyncKeyword.trimmedDescription)
                    }
                    if let throwsKeyword = funcDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier {
                        effectSpecifiers.append(throwsKeyword.trimmedDescription)
                    }
                    let effectString = effectSpecifiers.isEmpty ? "" : " " + effectSpecifiers.joined(separator: " ")
                    
                    // Get function body
                    let body = funcDecl.body?.statements.trimmedDescription ?? ""
                    
                    // Store as a computed property with function syntax
                    // We'll use the full function declaration as the "body"
                    let fullFunctionText = "\(modifierString)func \(functionName)(\(paramList))\(effectString) -> \(returnType) {\(body)}"
                    computedProperties.append((name: functionName, type: returnType, body: fullFunctionText))
                }
                continue
            }
            
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  let binding = varDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            
            let propertyName = identifier.identifier.text
            let typeAnnotation = binding.typeAnnotation?.type.trimmedDescription ?? ""
            
            // Check if it's declared with 'let' or 'var'
            let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)
            
            // Check if it's a computed property
            if let accessor = binding.accessorBlock {
                if let codeBlock = accessor.accessors.as(CodeBlockItemListSyntax.self) {
                    let body = codeBlock.trimmedDescription
                    
                    // Check if it has @SnapshotCompatible attribute
                    let hasSnapshotCompatible = varDecl.attributes.contains { attribute in
                        guard case let .attribute(attr) = attribute,
                              let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                            return false
                        }
                        return attrName == "SnapshotCompatible"
                    }
                    
                    if hasSnapshotCompatible {
                        computedProperties.append((name: propertyName, type: typeAnnotation, body: body))
                    }
                }
                continue
            }
            
            // Parse attributes
            var isStored = false
            var isRelated = false
            var isRelatedMany = false
            var isInverseRelated = false
            var isInverseRelatedMany = false
            var isSnapshotPrefetched = false
            var defaultValue: String? = nil
            var fallbackValue: String? = nil
            var isIndexed = false
            var isUnique = false
            var elementType: String? = nil
            var onDelete: String? = nil
            var referencingField: String? = nil
            var keyPath: String? = nil
            
            for attribute in varDecl.attributes {
                guard case let .attribute(attr) = attribute,
                      let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else {
                    continue
                }
                
                if attrName == "SnapshotPrefetched" {
                    isSnapshotPrefetched = true
                } else if attrName == "Stored" {
                    isStored = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            if argument.label?.text == "defaultValue" {
                                defaultValue = argument.expression.trimmedDescription
                            } else if argument.label?.text == "fallbackValue" {
                                fallbackValue = argument.expression.trimmedDescription
                            } else if argument.label?.text == "isIndexed" {
                                // Parse boolean value
                                let exprText = argument.expression.trimmedDescription
                                isIndexed = exprText == "true"
                            } else if argument.label?.text == "isUnique" {
                                // Parse boolean value
                                let exprText = argument.expression.trimmedDescription
                                isUnique = exprText == "true"
                            }
                        }
                    }
                } else if attrName == "Related" {
                    isRelated = true
                    if let arguments = attr.arguments?.as(LabeledExprListSyntax.self) {
                        for argument in arguments {
                            if argument.label?.text == "defaultValue" {
                                defaultValue = argument.expression.trimmedDescription
                            } else if argument.label?.text == "fallbackValue" {
                                fallbackValue = argument.expression.trimmedDescription
                            } else if argument.label?.text == "isUnique" {
                                // Parse boolean value
                                let exprText = argument.expression.trimmedDescription
                                isUnique = exprText == "true"
                            } else if argument.label?.text == "onDelete" {
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
            
            let isOptional = typeAnnotation.hasSuffix("?")

            if isStored {
                storedProperties.append((name: propertyName, type: typeAnnotation, isOptional: isOptional, hasDefault: defaultValue != nil, defaultValue: defaultValue, fallbackValue: fallbackValue, isIndexed: isIndexed, isUnique: isUnique, isLet: isLet))
            } else if isRelated {
                relatedProperties.append((name: propertyName, type: typeAnnotation, isOptional: isOptional, hasDefault: defaultValue != nil, defaultValue: defaultValue, fallbackValue: fallbackValue, isUnique: isUnique, onDelete: onDelete, isLet: isLet, isSnapshotPrefetched: isSnapshotPrefetched))
            } else if isRelatedMany, let element = elementType {
                let schemaName = "\(propertyName.prefix(1).uppercased())\(propertyName.dropFirst())RelationSchema"
                // Extract the collection element type from the type annotation (e.g., "Cargo.Snapshot" from "RelatedCollection<Cargo.Snapshot>")
                let collectionElementType = extractRelatedType(from: typeAnnotation)
                relatedManyProperties.append((name: propertyName, elementType: element, collectionElementType: collectionElementType, schemaType: schemaName, onDelete: onDelete, isSnapshotPrefetched: isSnapshotPrefetched))
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
        let stored: [(name: String, type: String, isOptional: Bool, hasDefault: Bool, defaultValue: String?, fallbackValue: String?, isIndexed: Bool, isUnique: Bool, isLet: Bool)]
        let related: [(name: String, type: String, isOptional: Bool, hasDefault: Bool, defaultValue: String?, fallbackValue: String?, isUnique: Bool, onDelete: String?, isLet: Bool, isSnapshotPrefetched: Bool)]
        let relatedMany: [(name: String, elementType: String, collectionElementType: String, schemaType: String, onDelete: String?, isSnapshotPrefetched: Bool)]
        let inverseRelated: [(name: String, type: String, referencingField: String)]
        let inverseRelatedMany: [(name: String, type: String, keyPath: String)]
        let computed: [(name: String, type: String, body: String)]
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
        let isPublic = isPublic(classDecl)
        let publicModifier = isPublic ? "public " : ""
        let withLifecycleFunctions = hasLifecycleFunctions(node)
        
        var members: [DeclSyntax] = []
        
        // Generate metadata and editableData properties
        members.append(
            """
            \(raw: publicModifier)let _metadata: ModelMetadata
            """
        )
        
        // Only generate _editableData if there are properties marked with @EditableValue or collections
        let hasEditableData = propertyInfo.stored.contains(where: { !$0.isLet })
            || propertyInfo.related.contains(where: { !$0.isLet })
            || !propertyInfo.relatedMany.isEmpty
            || !propertyInfo.inverseRelated.isEmpty 
            || !propertyInfo.inverseRelatedMany.isEmpty
        
        if hasEditableData {
            members.append(
                """
                let _editableData: EditableData
                """
            )
        }
        
        // Generate id property
        members.append(
            """
            \(raw: publicModifier)let id: UUID
            """
        )
                        
        // Generate first initializer (for creating new objects)
        members.append(generateCreateInitializer(
            className: className,
            propertyInfo: propertyInfo,
            isPublic: isPublic,
            withLifecycleFunctions: withLifecycleFunctions
        ))
        
        // Generate second initializer (for loading from database)
        members.append(generateRowInitializer(
            className: className,
            propertyInfo: propertyInfo,
            isPublic: isPublic,
            withLifecycleFunctions: withLifecycleFunctions
        ))
        
        members.append(try generateEditableDataClass(propertyInfo: propertyInfo, className: className))
        
        return members
    }
        
    private static func generateCreateInitializer(
        className: String,
        propertyInfo: PropertyInfo,
        isPublic: Bool,
        withLifecycleFunctions: Bool
    ) -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        // Build parameter list
        var parameters: [String] = ["db: Database"]
        
        // Add stored properties with defaults
        for prop in propertyInfo.stored {
            if prop.hasDefault {
                parameters.append("\(prop.name): \(prop.type) = DefaultValues.\(prop.name)")
            } else if prop.isOptional {
                parameters.append("\(prop.name): \(prop.type) = nil")
            } else {
                parameters.append("\(prop.name): \(prop.type)")
            }
        }
        
        // Add related properties (required ones first, optional ones with defaults)
        for prop in propertyInfo.related {
            if prop.hasDefault {
                parameters.append("\(prop.name): \(prop.type) = DefaultValues.\(prop.name)")
            } else if prop.isOptional {
                parameters.append("\(prop.name): \(prop.type) = nil")
            } else {
                parameters.append("\(prop.name): \(prop.type)")
            }
        }
        
        // Build the initializer body
        var bodyLines: [String] = [
            "let id = UUID.v7()"
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
        
        // Build EditableData initialization only with @EditableValue properties
        let hasEditableData = propertyInfo.stored.contains(where: { !$0.isLet })
            || propertyInfo.related.contains(where: { !$0.isLet })
            || !propertyInfo.relatedMany.isEmpty
            || !propertyInfo.inverseRelated.isEmpty 
            || !propertyInfo.inverseRelatedMany.isEmpty
        
        if hasEditableData {
            var editableParams: [String] = []
            for prop in propertyInfo.stored where !prop.isLet {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.related where !prop.isLet {
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
        
        // Assign let properties
        let storedLetProperties = propertyInfo.stored.filter { $0.isLet }
        let relatedLetProperties = propertyInfo.related.filter { $0.isLet }

        for prop in storedLetProperties {
            bodyLines.append("self.\(prop.name) = \(prop.name)")
        }

        for prop in relatedLetProperties {
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
        
        // Add afterInit() call if lifecycle functions are enabled
        if withLifecycleFunctions {
            bodyLines.append("")
            bodyLines.append("afterInit()")
        }
        
        let paramString = parameters.joined(separator: ", ")
        let bodyString = bodyLines.joined(separator: "\n        ")
        
        return """
        \(raw: publicModifier)init(\(raw: paramString))
        {
            \(raw: bodyString)
        }
        """
    }
    
    private static func generateRowInitializer(
        className: String,
        propertyInfo: PropertyInfo,
        isPublic: Bool,
        withLifecycleFunctions: Bool
    ) -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var bodyLines: [String] = [
            "let id: UUID = try row.get(\"id\")"
        ]
        
        // Extract stored properties from row
        for prop in propertyInfo.stored {
            if prop.fallbackValue != nil {
                bodyLines.append("let \(prop.name): \(prop.type) = try row.get(\"\(prop.name)\", fallback: FallbackValues.\(prop.name))")
            } else {
                bodyLines.append("let \(prop.name): \(prop.type) = try row.get(\"\(prop.name)\")")
            }
        }
        
        // Extract related properties from row
        for prop in propertyInfo.related {
            if prop.fallbackValue != nil {
                bodyLines.append("let \(prop.name): \(prop.type) = try await row.get(\"\(prop.name)\", fallback: FallbackValues.\(prop.name))")
            } else {
                bodyLines.append("let \(prop.name): \(prop.type) = try await row.get(\"\(prop.name)\")")
            }
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
        
        // Build EditableData initialization only with @EditableValue properties
        let hasEditableData = propertyInfo.stored.contains(where: { !$0.isLet })
            || propertyInfo.related.contains(where: { !$0.isLet })
            || !propertyInfo.relatedMany.isEmpty
            || !propertyInfo.inverseRelated.isEmpty 
            || !propertyInfo.inverseRelatedMany.isEmpty
            
        if hasEditableData {
            var editableParams: [String] = []
            for prop in propertyInfo.stored where !prop.isLet {
                editableParams.append("\(prop.name): \(prop.name)")
            }
            for prop in propertyInfo.related where !prop.isLet {
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
        
        // Assign let properties
        let storedLetProperties = propertyInfo.stored.filter { $0.isLet }
        let relatedLetProperties = propertyInfo.related.filter { $0.isLet }

        for prop in storedLetProperties {
            bodyLines.append("self.\(prop.name) = \(prop.name)")
        }

        for prop in relatedLetProperties {
            bodyLines.append("self.\(prop.name) = \(prop.name)")
        }

        // Add afterInit() call if lifecycle functions are enabled
        if withLifecycleFunctions {
            bodyLines.append("")
            bodyLines.append("afterInit()")
        }

        let bodyString = bodyLines.joined(separator: "\n        ")
        
        return """
        \(raw: publicModifier)init(db: Database, row: Database.Row) async throws
        {
            \(raw: bodyString)
        }
        """
    }
    
    // MARK: - Extension Generation Helpers
    
    private static func generateModelProtocolMethods(
        className: String,
        propertyInfo: PropertyInfo,
        classDecl: ClassDeclSyntax,
        isPublic: Bool,
        withLifecycleFunctions: Bool
    ) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var methods = [String]()
        
        // _beginAutoupdating
        var autoupdatingCalls = ["_metadata._beginAutoupdating(model: self)"]
        for prop in propertyInfo.related {
            if prop.isLet {
                // Non-editable properties are direct properties
                if prop.isOptional {
                    autoupdatingCalls.append("\(prop.name)?._beginAutoupdating()")
                } else {
                    autoupdatingCalls.append("\(prop.name)._beginAutoupdating()")
                }
            } else {
                // Editable properties are in _editableData
                if prop.isOptional {
                    autoupdatingCalls.append("_editableData.\(prop.name)?._beginAutoupdating()")
                } else {
                    autoupdatingCalls.append("_editableData.\(prop.name)._beginAutoupdating()")
                }
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
        \(publicModifier)func _beginAutoupdating()
        {
            \(autoupdatingCalls.joined(separator: "\n    "))
        }
        """)
        
        // _hasPendingChanges
        var hasPendingChecks = ["_metadata._hasPendingChanges"]
        for prop in propertyInfo.related {
            if prop.isLet {
                // Non-editable properties are direct properties
                if prop.isOptional {
                    hasPendingChecks.append("\(prop.name)?._hasPendingChanges")
                } else {
                    hasPendingChecks.append("\(prop.name)._hasPendingChanges")
                }
            } else {
                // Editable properties are in _editableData
                if prop.isOptional {
                    hasPendingChecks.append("_editableData.\(prop.name)?._hasPendingChanges")
                } else {
                    hasPendingChecks.append("_editableData.\(prop.name)._hasPendingChanges")
                }
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
        \(publicModifier)var _hasPendingChanges: Bool {
            let hasChanges = [
                \(hasPendingChecks.joined(separator: ",\n        "))
            ]
            .contains(true)
            return hasChanges
        }
        """)
        
        // _beginSaving
        var beginSavingCalls = ["try await _metadata._beginSaving(changeset: changeset)"]
        for prop in propertyInfo.related {
            if prop.isLet {
                // Non-editable properties are direct properties
                if prop.isOptional {
                    beginSavingCalls.append("try await \(prop.name)?._beginSaving(changeset: changeset)")
                } else {
                    beginSavingCalls.append("try await \(prop.name)._beginSaving(changeset: changeset)")
                }
            } else {
                // Editable properties are in _editableData
                if prop.isOptional {
                    beginSavingCalls.append("try await _editableData.\(prop.name)?._beginSaving(changeset: changeset)")
                } else {
                    beginSavingCalls.append("try await _editableData.\(prop.name)._beginSaving(changeset: changeset)")
                }
            }
        }
        for prop in propertyInfo.relatedMany {
            beginSavingCalls.append("try await _editableData.\(prop.name)._beginSaving(changeset: changeset)")
        }
        for prop in propertyInfo.inverseRelated {
            beginSavingCalls.append("try await _editableData.\(prop.name)._beginSaving(changeset: changeset)")
        }
        for prop in propertyInfo.inverseRelatedMany {
            beginSavingCalls.append("try await _editableData.\(prop.name)._beginSaving(changeset: changeset)")
        }
        
        let beginSavingBody = withLifecycleFunctions 
            ? "try await beforeSave()\n    \(beginSavingCalls.joined(separator: "\n    "))"
            : beginSavingCalls.joined(separator: "\n    ")
        
        methods.append("""
        \(publicModifier)nonisolated(nonsending) func _beginSaving(changeset: Changeset) async throws
        {
            \(beginSavingBody)
        }
        """)
        
        // _endSaving
        var endSavingCalls = [
            "_metadata._endSaving(success: success, transactionId: transactionId)"
        ]
        for prop in propertyInfo.related {
            if prop.isLet {
                // Non-editable properties are direct properties
                if prop.isOptional {
                    endSavingCalls.append("\(prop.name)?._endSaving(success: success, transactionId: transactionId)")
                } else {
                    endSavingCalls.append("\(prop.name)._endSaving(success: success, transactionId: transactionId)")
                }
            } else {
                // Editable properties are in _editableData
                if prop.isOptional {
                    endSavingCalls.append("_editableData.\(prop.name)?._endSaving(success: success, transactionId: transactionId)")
                } else {
                    endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transactionId: transactionId)")
                }
            }
        }
        for prop in propertyInfo.relatedMany {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transactionId: transactionId)")
        }
        for prop in propertyInfo.inverseRelated {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transactionId: transactionId)")
        }
        for prop in propertyInfo.inverseRelatedMany {
            endSavingCalls.append("_editableData.\(prop.name)._endSaving(success: success, transactionId: transactionId)")
        }
        
        // Add afterSave() call if lifecycle functions are enabled
        if withLifecycleFunctions {
            endSavingCalls.append("if success { afterSave() }")
        }
        
        methods.append("""
        \(publicModifier)func _endSaving(success: Bool, transactionId: UUID)
        {
            let wasNew = _metadata.objectStatus == .new
            \(endSavingCalls.joined(separator: "\n    "))
            if wasNew, _metadata.objectStatus != .new {
                _beginAutoupdatingIfOnMainActor()
            }
        }
        """)
        
        // _update
        var updateCalls = [String]()
        for prop in propertyInfo.stored where !prop.isLet {
            updateCalls.append("try await update(field: \"\(prop.name)\", writableKeyPath: \\._editableData.\(prop.name), newValue: updatedFields[\"\(prop.name)\"])")
        }
        for prop in propertyInfo.related where !prop.isLet {
            updateCalls.append("try await update(field: \"\(prop.name)\", writableKeyPath: \\._editableData.\(prop.name), newValue: updatedFields[\"\(prop.name)\"])")
        }
        
        methods.append("""
        \(publicModifier)func _update(with changes: ChangedObject) async throws
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
                if prop.isLet {
                    // Non-editable properties are direct properties
                    if prop.isOptional {
                        cascadeCalls.append("\(prop.name)?._cascadeDeletion()")
                    } else {
                        cascadeCalls.append("\(prop.name)._cascadeDeletion()")
                    }
                } else {
                    // Editable properties are in _editableData
                    if prop.isOptional {
                        cascadeCalls.append("_editableData.\(prop.name)?._cascadeDeletion()")
                    } else {
                        cascadeCalls.append("_editableData.\(prop.name)._cascadeDeletion()")
                    }
                }
            }
        }
        for prop in propertyInfo.relatedMany {
            if prop.onDelete == ".cascade" {
                cascadeCalls.append("_editableData.\(prop.name)._cascadeDeletion()")
            }
        }
        
        methods.append("""
        \(publicModifier)func _cascadeDeletion()
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
        propertyInfo: PropertyInfo,
        isPublic: Bool
    ) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var relatedTypes = Set<String>()
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            relatedTypes.insert("\(baseType).Model.Schema.self")
        }
        for prop in propertyInfo.relatedMany {
            relatedTypes.insert("\(prop.elementType).Model.Schema.self")
            relatedTypes.insert("\(prop.schemaType).self")
        }
        
        var columns = ["Columns.id"]
        var columnDefs = ["\(publicModifier)static let id = RequiredSchema.Column(name: \"id\", type: UUID.self, collation: \"NOCASE\")"]
        var indexes = [String]()
        
        for prop in propertyInfo.stored {
            columns.append("Columns.\(prop.name)")
            
            // Check if the property type is UUID to add COLLATE NOCASE
            let normalizedType = prop.type.replacingOccurrences(of: "?", with: "").trimmingCharacters(in: .whitespaces)
            let collationParam = (normalizedType == "UUID" || normalizedType == "String") ? ", collation: \"NOCASE\"" : ""
            
            columnDefs.append("\(publicModifier)static let \(prop.name) = RequiredSchema.Column(name: \"\(prop.name)\", type: \(prop.type).self\(collationParam))")
            
            // Add index if isIndexed is true or isUnique is true
            if prop.isIndexed {
                indexes.append(".init(name: \"idx_\(className)_\(prop.name)\", isUnique: \(prop.isUnique), columns: [Columns.\(prop.name)])")
            } else if prop.isUnique {
                // If only isUnique is true but isIndexed is false, still create an index (unique constraint requires an index)
                indexes.append(".init(name: \"idx_\(className)_\(prop.name)\", isUnique: true, columns: [Columns.\(prop.name)])")
            }
        }
        
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            let referencedTableName = baseType == className ? "\"\(className)\"" : "\(baseType).Model._tableName"
            columns.append("Columns.\(prop.name)")
            // Foreign key columns referencing id (which is UUID) should also have COLLATE NOCASE
            columnDefs.append("\(publicModifier)static let \(prop.name) = RequiredSchema.Column(name: \"\(prop.name)\", type: \(baseType).self, referencedTable: \(referencedTableName), collation: \"NOCASE\")")
            indexes.append(".init(name: \"idx_\(className)_\(prop.name)\", isUnique: false, columns: [Columns.\(prop.name)])")
        }
        
        // Prevent circular reference
        relatedTypes.remove("\(className).Model.Schema.self")
        
        return """
        \(raw: publicModifier)final class Schema: ModelSchema
        {
            \(raw: publicModifier)typealias Model = \(raw: className)
            
            \(raw: publicModifier)static let related: [any ModelSchema.Type] = [\(raw: relatedTypes.joined(separator: ", "))]
            
            \(raw: publicModifier)struct Columns
            {
                \(raw: columnDefs.joined(separator: "\n        "))
            }
        
            \(raw: publicModifier)static let table = RequiredSchema.Table(name: "\(raw: className)", columns: [
                \(raw: columns.joined(separator: ",\n        "))
            ], indexes: [
                \(raw: indexes.joined(separator: ",\n        "))
            ])
        }
        """
    }
    
    private static func generateRelationshipModelSchema(
        className: String,
        property: (name: String, elementType: String, collectionElementType: String, schemaType: String, onDelete: String?, isSnapshotPrefetched: Bool)
    ) throws -> DeclSyntax {
        let deletionPolicy = property.onDelete ?? ".ignore"
        let tableName = "\(className)_\(property.name)__\(property.elementType)"
        
        return """
        nonisolated final class \(raw: property.schemaType): RelationshipModelSchema
        {
            typealias Parent = \(raw: className)
            typealias Element = \(raw: property.collectionElementType)
            typealias Model = ManyToMany<\(raw: property.schemaType)>.JunctionModel

            static let deletionPolicy: DeletionPolicy = \(raw: deletionPolicy)
            
            static let table = RelationshipModelSchemaDefaults.getTable(name: "\(raw: tableName)", parentTable: Parent.Model.Schema.table.name, elementTable: Element.Model.Schema.table.name)
        }
        """
    }
    
    private static func generateDefaultValuesStruct(propertyInfo: PropertyInfo, isPublic: Bool = false) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var defaultVars = [String]()
        
        for prop in propertyInfo.stored where prop.hasDefault {
            if let defaultValue = prop.defaultValue {
                defaultVars.append("\(publicModifier)static var \(prop.name): \(prop.type) { \(defaultValue) }")
            }
        }
        
        for prop in propertyInfo.related where prop.isOptional {
            defaultVars.append("\(publicModifier)static var \(prop.name): \(prop.type) { nil }")
        }
        
        return """
        \(raw: publicModifier)struct DefaultValues
        {
            \(raw: defaultVars.joined(separator: "\n    "))
        }
        """
    }
    
    private static func generateFallbackValuesStruct(propertyInfo: PropertyInfo, isPublic: Bool = false) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var fallbackVars = [String]()
        
        for prop in propertyInfo.stored {
            if let fallbackValue = prop.fallbackValue {
                fallbackVars.append("\(publicModifier)static var \(prop.name): \(prop.type) { \(fallbackValue) }")
            }
        }

        for prop in propertyInfo.related {
            if let fallbackValue = prop.fallbackValue {
                fallbackVars.append("\(publicModifier)static var \(prop.name): \(prop.type) { \(fallbackValue) }")
            }
        }

        guard !fallbackVars.isEmpty else {
            return """
            \(raw: publicModifier)struct FallbackValues {}
            """
        }
        
        return """
        \(raw: publicModifier)struct FallbackValues
        {
            \(raw: fallbackVars.joined(separator: "\n    "))
        }
        """
    }
    
    private static func generateEditableDataClass(propertyInfo: PropertyInfo, className: String) throws -> DeclSyntax {
        var properties = [String]()
        var initParams = [String]()
        var initAssignments = [String]()
        
        // Only include var properties
        for prop in propertyInfo.stored where !prop.isLet {
            properties.append("var \(prop.name): \(prop.type)")
            initParams.append("\(prop.name): \(prop.type)")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        for prop in propertyInfo.related where !prop.isLet {
            properties.append("var \(prop.name): \(prop.type)")
            initParams.append("\(prop.name): \(prop.type)")
            initAssignments.append("self.\(prop.name) = \(prop.name)")
        }
        
        // RelatedMany, InverseRelated, and InverseRelatedMany are always included in EditableData
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
        propertyInfo: PropertyInfo,
        isPublic: Bool
    ) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var properties = ["\(publicModifier)let id: UUID"]
        
        for prop in propertyInfo.stored {
            properties.append("\(publicModifier)let \(prop.name): \(prop.type)")
        }
        
        for prop in propertyInfo.related {
            properties.append("\(publicModifier)let \(prop.name): \(prop.type)")
        }
        
        return """
        nonisolated \(raw: publicModifier)struct QueryProxy: SwiftLite.QueryProxy
        {
            \(raw: properties.joined(separator: "\n    "))
        }
        """
    }
    
    private static func generateSnapshotStruct(
        className: String,
        propertyInfo: PropertyInfo,
        classDecl: ClassDeclSyntax,
        isPublic: Bool
    ) throws -> DeclSyntax {
        let publicModifier = isPublic ? "public " : ""
        
        var computedProps = [String]()
        for prop in propertyInfo.computed {
            // Check if this is a function (body contains "func ")
            if prop.body.contains("func ") {
                // It's a function - use the full function declaration
                computedProps.append("\(publicModifier)\(prop.body)")
            } else {
                // It's a computed property - wrap in var declaration
                computedProps.append("""
                \(publicModifier)var \(prop.name): \(prop.type) {
                    \(prop.body)
                }
                """)
            }
        }
        
        var storedProps = [
            "\(publicModifier)let _metadata: SnapshotMetadata<Self>",
            "",
            "\(publicModifier)let id: UUID"
        ]
        
        var rowExtractions = ["let id: UUID = try row.get(\"id\")", "", "self._metadata = SnapshotMetadata<Self>(id: id, db: db)", "", "self.id = id"]
        
        for prop in propertyInfo.stored {
            storedProps.append("\(publicModifier)let \(prop.name): \(prop.type)")
            if prop.fallbackValue != nil {
                rowExtractions.append("self.\(prop.name) = try row.get(\"\(prop.name)\", fallback: FallbackValues.\(prop.name))")
            } else {
                rowExtractions.append("self.\(prop.name) = try row.get(\"\(prop.name)\")")
            }
        }
        
        for prop in propertyInfo.related {
            let baseType = prop.type.replacingOccurrences(of: "?", with: "").replacingOccurrences(of: ".Snapshot", with: "")
            
            // Handle @SnapshotPrefetched @Related properties
            if prop.isSnapshotPrefetched {
                if prop.isOptional {
                    storedProps.append("\(publicModifier)let \(prop.name): \(baseType).Snapshot?")
                    rowExtractions.append("self.\(prop.name) = try await row.get(\"\(prop.name)\")")
                } else {
                    storedProps.append("\(publicModifier)let \(prop.name): \(baseType).Snapshot")
                    rowExtractions.append("self.\(prop.name) = try await row.get(\"\(prop.name)\")")
                }
            } else if prop.isOptional {
                storedProps.append("")
                storedProps.append("\(publicModifier)let _\(prop.name): DirectRelationReference<\(baseType)>?")
                storedProps.append("\(publicModifier)var \(prop.name): \(baseType).Snapshot? {")
                storedProps.append("    get async throws {")
                storedProps.append("        guard let _\(prop.name) else { return nil }")
                storedProps.append("        return try await _metadata.db.resolve(_\(prop.name))")
                storedProps.append("    }")
                storedProps.append("}")
                rowExtractions.append("self._\(prop.name) = try row.get(\"\(prop.name)\")")
            } else {
                storedProps.append("")
                storedProps.append("\(publicModifier)let _\(prop.name): DirectRelationReference<\(baseType)>")
                storedProps.append("\(publicModifier)var \(prop.name): \(baseType).Snapshot {")
                storedProps.append("    get async throws {")
                storedProps.append("        try await _metadata.db.resolve(_\(prop.name))")
                storedProps.append("    }")
                storedProps.append("}")
                rowExtractions.append("self._\(prop.name) = try row.get(\"\(prop.name)\")")
            }
        }
        
        // Handle @RelatedMany properties with @SnapshotPrefetched
        for prop in propertyInfo.relatedMany where prop.isSnapshotPrefetched {
            storedProps.append("\(publicModifier)let \(prop.name): [\(prop.elementType).Snapshot]")
            rowExtractions.append("self.\(prop.name) = try await row.get(schema: \(prop.schemaType).self, parentId: id)")
        }
        
        return """
        nonisolated \(raw: publicModifier)struct Snapshot: ModelSnapshot
        {
            \(raw: publicModifier)typealias Model = \(raw: className)
            
            \(raw: computedProps.joined(separator: "\n    "))
            
            \(raw: storedProps.joined(separator: "\n    "))
        
            \(raw: publicModifier)init(db: Database, row: Database.Row) async throws
            {
                \(raw: rowExtractions.joined(separator: "\n        "))
            }
        }
        """
    }
}

