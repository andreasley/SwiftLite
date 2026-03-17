import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/// A macro that generates async loading infrastructure for a SwiftUI View
/// 
/// This macro analyzes `@EditableObject` properties in a View and generates:
/// - An `ItemsContainer` that conforms to `LoadableItemsContainer`
/// - A `loading()` static method for creating the view with references
/// - A `PreloadView` that handles the loading lifecycle
///
/// Usage:
/// ```swift
/// // With default status view (DefaultStatusView)
/// @AsyncLoadingView
/// struct MyView: View {
///     @EditableObject(autosaving: true) var car: Car
///     @EditableObject(autosaving: false) var engine: Engine
///     // ...
/// }
///
/// // With custom status view
/// @AsyncLoadingView<CustomStatusView>
/// struct MyView: View {
///     @EditableObject(autosaving: true) var car: Car
///     @EditableObject(autosaving: false) var engine: Engine
///     // ...
/// }
/// ```
public struct AsyncLoadingViewMacro: MemberMacro, ExtensionMacro
{
    // MARK: - Diagnostics
    
    enum AsyncLoadingViewDiagnostic: String, DiagnosticMessage {
        case requiresView
        case noEditableObjects
        
        var severity: DiagnosticSeverity {
            switch self {
            case .requiresView, .noEditableObjects:
                return .error
            }
        }
        
        var message: String {
            switch self {
            case .requiresView:
                return "@AsyncLoadingView can only be applied to View types"
            case .noEditableObjects:
                return "@AsyncLoadingView requires at least one @EditableObject property"
            }
        }
        
        var diagnosticID: MessageID {
            MessageID(domain: "SwiftLite", id: rawValue)
        }
    }
    
    // MARK: - Property Analysis
    
    struct EditableObjectProperty {
        let name: String
        let typeName: String
        let autosaving: Bool
        
        var referenceName: String {
            "__reference_\(name)"
        }
    }
    
    /// Extracts @EditableObject properties from the struct members
    private static func extractEditableObjects(
        from members: MemberBlockItemListSyntax
    ) -> [EditableObjectProperty] {
        var properties: [EditableObjectProperty] = []
        
        for member in members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            
            // Check if it has @EditableObject attribute
            guard let editableObjectAttr = varDecl.attributes.first(where: { attr in
                guard case .attribute(let attrSyntax) = attr else { return false }
                return attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "EditableObject"
            }) else { continue }
            
            // Extract autosaving parameter
            var autosaving = true // default
            if case .attribute(let attrSyntax) = editableObjectAttr,
               let arguments = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                for argument in arguments {
                    if argument.label?.text == "autosaving",
                       let boolExpr = argument.expression.as(BooleanLiteralExprSyntax.self) {
                        autosaving = boolExpr.literal.text == "true"
                    }
                }
            }
            
            // Extract property name and type
            guard let binding = varDecl.bindings.first,
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeAnnotation = binding.typeAnnotation else { continue }
            
            let propertyName = pattern.identifier.text
            let typeName = typeAnnotation.type.trimmedDescription
            
            properties.append(EditableObjectProperty(
                name: propertyName,
                typeName: typeName,
                autosaving: autosaving
            ))
        }
        
        return properties
    }
    
    /// Extracts the StatusView type from the attribute, defaulting to DefaultStatusView
    private static func extractStatusViewType(
        from node: AttributeSyntax
    ) -> String {
        // Check for generic argument like @AsyncLoadingView<DefaultStatusView>
        if let genericArgs = node.attributeName.as(IdentifierTypeSyntax.self)?.genericArgumentClause {
            return genericArgs.arguments.first?.argument.trimmedDescription ?? "DefaultStatusView"
        }
        return "DefaultStatusView"
    }
    
    // MARK: - Code Generation
    
    /// Generates the ItemsContainer class
    private static func generateItemsContainer(
        properties: [EditableObjectProperty]
    ) -> DeclSyntax {
        let referenceProperties = properties.map { prop in
            """
            let \(prop.referenceName): DatabaseObjectReference<\(prop.typeName)>
            private(set) var \(prop.name): \(prop.typeName)?
            """
        }.joined(separator: "\n        ")
        
        let initParameters = properties.map { prop in
            "\(prop.referenceName): DatabaseObjectReference<\(prop.typeName)>"
        }.joined(separator: ", ")
        
        let initAssignments = properties.map { prop in
            "self.\(prop.referenceName) = \(prop.referenceName)"
        }.joined(separator: "\n            ")
        
        let loadStatements = properties.map { prop in
            "\(prop.name) = try await \(prop.referenceName).resolve()"
        }.joined(separator: "\n            ")
        
        // Only save properties with autosaving: true
        let autosavingProperties = properties.filter { $0.autosaving }
        let saveStatements = autosavingProperties.isEmpty 
            ? "// No autosaving properties to save"
            : autosavingProperties.map { prop in
                "try await \(prop.name)?.save()"
            }.joined(separator: "\n            ")
        
        let unloadStatements = properties.map { prop in
            "\(prop.name) = nil"
        }.joined(separator: "\n            ")
        
        // Only check pending changes for autosaving properties
        let hasPendingChangesChecks = autosavingProperties.isEmpty
            ? "false"
            : autosavingProperties.map { prop in
                "\(prop.name)?._hasPendingChanges"
            }.joined(separator: ",\n                ")
        
        let hasPendingChangesBody = autosavingProperties.isEmpty
            ? "return false"
            : """
            let hasChanges = [
                    \(hasPendingChangesChecks),
                ]
                .contains(true)
                return hasChanges
            """
        
        let hasBeenDeletedChecks = properties.map { prop in
            "\(prop.name)?.hasBeenDeletedFromDatabase"
        }.joined(separator: ",\n                ")
        
        let code = """
        @Observable
        class ItemsContainer: LoadableItemsContainer
        {
            \(referenceProperties)
        
            init(\(initParameters))
            {
                \(initAssignments)
            }
        
            func load() async throws
            {
                \(loadStatements)
            }
            
            func save() async throws
            {
                \(saveStatements)
            }
            
            func unload()
            {
                \(unloadStatements)
            }
            
            var anyItemHasPendingChanges: Bool
            {
                \(hasPendingChangesBody)
            }
        
            var anyItemHasBeenDeleted: Bool
            {
                let hasChanges = [
                    \(hasBeenDeletedChecks),
                ]
                .contains(true)
                return hasChanges
            }
        }
        """
        
        return DeclSyntax(stringLiteral: code)
    }
    
    /// Generates the loading() static method
    private static func generateLoadingMethod(
        viewName: String,
        properties: [EditableObjectProperty]
    ) -> DeclSyntax {
        let parameters = properties.map { prop in
            "\(prop.name): any DatabaseObjectReferenceConvertible<\(prop.typeName)>"
        }.joined(separator: ", ")
        
        let referenceArguments = properties.map { prop in
            "\(prop.referenceName): \(prop.name).getObjectReference()"
        }.joined(separator: ", ")
        
        let code = """
        static func loading(\(parameters)) -> PreloadView
        {
            let items = ItemsContainer(\(referenceArguments))
            return PreloadView(items: items)
        }
        """
        
        return DeclSyntax(stringLiteral: code)
    }
    
    /// Generates the PreloadView struct
    private static func generatePreloadView(
        viewName: String,
        properties: [EditableObjectProperty],
        statusViewType: String
    ) -> DeclSyntax {
        let unwrappedConditions = properties.map { prop in
            "let \(prop.name) = items.\(prop.name)"
        }.joined(separator: ", ")
        
        let viewInitProperties = properties.map { prop in
            "\(prop.name): .init(wrappedValue: \(prop.name), autosaving: \(prop.autosaving))"
        }.joined(separator: ", ")
        
        let code = """
        struct PreloadView: View
        {
            @State var items: ItemsContainer
        
            @ViewBuilder
            var body: some View {
                Group {
                    if items.anyItemHasBeenDeleted {
                        ContentUnavailableView("One of the objects in this view has been deleted", systemImage: "trash")
                    } else if \(unwrappedConditions) {
                        \(viewName)(\(viewInitProperties))
                    }
                }
                .handleModelLifecycle(items: items, statusView: \(statusViewType).self)
            }
        }
        """
        
        return DeclSyntax(stringLiteral: code)
    }
    
    // MARK: - ExtensionMacro Implementation
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Validate it's a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: AsyncLoadingViewDiagnostic.requiresView
            ))
            return []
        }
        
        let viewName = structDecl.name.text
        
        // Extract StatusView type (defaults to DefaultStatusView)
        let statusViewType = extractStatusViewType(from: node)
        
        // Extract @EditableObject properties
        let properties = extractEditableObjects(from: structDecl.memberBlock.members)
        
        guard !properties.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: AsyncLoadingViewDiagnostic.noEditableObjects
            ))
            return []
        }
        
        // Generate extension members (ItemsContainer is now added as a member of the struct)
        let loadingMethod = generateLoadingMethod(viewName: viewName, properties: properties)
        let preloadView = generatePreloadView(
            viewName: viewName,
            properties: properties,
            statusViewType: statusViewType
        )
        
        let typealiasDecl: DeclSyntax = """
        typealias PreloadViewStatusView = \(raw: statusViewType)
        """
        
        // Create extension without ItemsContainer
        let extensionDecl = try ExtensionDeclSyntax(
            """
            @MainActor
            extension \(raw: viewName)
            {
                \(typealiasDecl)
                
                \(loadingMethod)
                
                \(preloadView)
            }
            """
        )
        
        return [extensionDecl]
    }
    
    // MARK: - MemberMacro Implementation
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Validate it's a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(Diagnostic(
                node: node,
                message: AsyncLoadingViewDiagnostic.requiresView
            ))
            return []
        }
        
        // Extract @EditableObject properties
        let properties = extractEditableObjects(from: structDecl.memberBlock.members)
        
        guard !properties.isEmpty else {
            context.diagnose(Diagnostic(
                node: node,
                message: AsyncLoadingViewDiagnostic.noEditableObjects
            ))
            return []
        }
        
        // Generate ItemsContainer as a member of the original struct
        let itemsContainer = generateItemsContainer(properties: properties)
        
        return [itemsContainer]
    }
}
