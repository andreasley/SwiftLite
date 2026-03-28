//
//  OperationType.swift
//  SwiftLite
//
//  Created by Andreas on 28.03.2026.
//


    public enum OperationType: String, Sendable, Codable
    {
        // Schema operations
        case tableCreated = "table_created"
        case columnAdded = "column_added"
        case indexCreated = "index_created"
        case indexDropped = "index_dropped"
        
        // Data operations
        case rowCreated = "row_created"
        case rowDeleted = "row_deleted"
        case fieldUpdated = "field_updated"
    }
