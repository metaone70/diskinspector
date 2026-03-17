//
//  DiskInspectorApp.swift
//  DiskInspector
//
//  Created by server on 17.03.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct DiskInspectorApp: App {
    var body: some Scene {
        DocumentGroup(editing: .itemDocument, migrationPlan: DiskInspectorMigrationPlan.self) {
            ContentView()
        }
    }
}

extension UTType {
    static var itemDocument: UTType {
        UTType(importedAs: "com.example.item-document")
    }
}

struct DiskInspectorMigrationPlan: SchemaMigrationPlan {
    static var schemas: [VersionedSchema.Type] = [
        DiskInspectorVersionedSchema.self,
    ]

    static var stages: [MigrationStage] = [
        // Stages of migration between VersionedSchema, if required.
    ]
}

struct DiskInspectorVersionedSchema: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        Item.self,
    ]
}
