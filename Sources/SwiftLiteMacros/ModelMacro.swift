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
        return []
    }
    
    // MARK: MemberMacro
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax]
    {
        return []
    }
}

