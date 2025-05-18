//
//  Sensory_Overload_DetectorApp.swift
//  AuSense
//
//  Created by Anshu Adiga on 4/11/25.
//

import SwiftUI
import SwiftData

@main
struct Sensory_Overload_DetectorApp: App {
    @StateObject private var sensorConnectionService = SensorConnectionService()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SensorReading.self,
            UserSettings.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sensorConnectionService)
        }
        .modelContainer(sharedModelContainer)
    }
}
