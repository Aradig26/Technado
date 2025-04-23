//
//  ContentView.swift
//  Sensory Overload Detector
//
//  Created by Anshu Adiga on 4/11/25.
//

import SwiftUI
import SwiftData
import CoreBluetooth

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var readings: [SensorReading]
    @Query private var settings: [UserSettings]
    @EnvironmentObject private var sensorService: SensorConnectionService
    
    @State private var selectedTab = 0
    @State private var showingDeviceSheet = false
    @State private var isCalibrating = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Dashboard Tab
            dashboardView
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }
                .tag(0)
            
            // MARK: - History Tab
            historyView
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(1)
            
            // MARK: - Settings Tab
            settingsView
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .onAppear {
            // Ensure we have a settings object
            if settings.isEmpty {
                let newSettings = UserSettings()
                modelContext.insert(newSettings)
                sensorService.updateSettings(newSettings)
            } else {
                sensorService.updateSettings(settings[0])
            }
        }
        .sheet(isPresented: $showingDeviceSheet) {
            DeviceListView(isPresented: $showingDeviceSheet)
                .environmentObject(sensorService)
        }
    }
    
    // MARK: - Dashboard View
    private var dashboardView: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Connection Status
                connectionStatusCard
                
                // Current Readings
                currentReadingsCard
                
                // Risk Level
                riskLevelCard
                
                Spacer()
                
                // Connect Button
                if !sensorService.isConnected {
                    Button(action: {
                        showingDeviceSheet = true
                        sensorService.startScanning()
                    }) {
                        Text("Connect to Sensor")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: {
                        sensorService.disconnect()
                    }) {
                        Text("Disconnect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Sensory Monitor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isCalibrating = true
                    }) {
                        Label("Calibrate", systemImage: "heart")
                    }
                    .disabled(!sensorService.isConnected)
                }
            }
            .alert("Calibrate Heart Rate", isPresented: $isCalibrating) {
                Button("Cancel", role: .cancel) { }
                Button("Set Baseline") {
                    if let reading = sensorService.lastReading {
                        sensorService.calibrateHeartRate(with: reading.heartRate)
                    }
                }
            } message: {
                Text("Set your current heart rate as the baseline? Make sure you are calm and relaxed.")
            }
        }
    }
    
    private var connectionStatusCard: some View {
        VStack {
            HStack {
                Image(systemName: sensorService.isConnected ? "wifi" : "wifi.slash")
                    .foregroundColor(sensorService.isConnected ? .green : .red)
                Text(sensorService.isConnected ? "Connected" : "Disconnected")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
    }
    
    private var currentReadingsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Current Readings")
                    .font(.headline)
                Spacer()
            }
            
            if let reading = sensorService.lastReading {
                HStack {
                    SensorReadingView(
                        icon: "ear",
                        value: String(format: "%.1f dB", reading.soundLevel),
                        thresholdExceeded: reading.soundLevel > (settings.first?.soundThreshold ?? 85.0)
                    )
                    
                    Divider()
                    
                    SensorReadingView(
                        icon: "lightbulb",
                        value: String(format: "%.0f lux", reading.lightLevel),
                        thresholdExceeded: reading.lightLevel > (settings.first?.lightThreshold ?? 1000.0)
                    )
                    
                    Divider()
                    
                    let baselineRate = sensorService.baselineHeartRate
                    let increase = ((reading.heartRate - baselineRate) / baselineRate) * 100
                    let thresholdExceeded = increase > (settings.first?.heartRateThreshold ?? 20.0)
                    
                    SensorReadingView(
                        icon: "heart",
                        value: String(format: "%.0f BPM", reading.heartRate),
                        subvalue: String(format: "+%.1f%%", increase),
                        thresholdExceeded: thresholdExceeded
                    )
                }
            } else {
                HStack {
                    SensorReadingView(icon: "ear", value: "-- dB", thresholdExceeded: false)
                    Divider()
                    SensorReadingView(icon: "lightbulb", value: "-- lux", thresholdExceeded: false)
                    Divider()
                    SensorReadingView(icon: "heart", value: "-- BPM", thresholdExceeded: false)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
    
    private var riskLevelCard: some View {
        let isOverload = sensorService.lastReading?.isOverload ?? false
        
        return VStack(spacing: 10) {
            HStack {
                Text("Sensory Overload Risk")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Image(systemName: isOverload ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(isOverload ? .red : .green)
                
                VStack(alignment: .leading) {
                    Text(isOverload ? "High Risk" : "Low Risk")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(isOverload ? "Environmental conditions may cause sensory overload" : "Current conditions appear safe")
                        .font(.caption)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isOverload ? Color.red : Color.green, lineWidth: 2)
        )
    }
    
    // MARK: - History View
    private var historyView: some View {
        NavigationStack {
            List {
                ForEach(readings.sorted { $0.timestamp > $1.timestamp }) { reading in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(reading.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                                .font(.headline)
                            
                            Spacer()
                            
                            if reading.isOverload {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        HStack {
                            Label(String(format: "%.1f dB", reading.soundLevel), systemImage: "ear")
                            Spacer()
                            Label(String(format: "%.0f lux", reading.lightLevel), systemImage: "lightbulb")
                            Spacer()
                            Label(String(format: "%.0f BPM", reading.heartRate), systemImage: "heart")
                        }
                        .font(.caption)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteReadings)
            }
            .navigationTitle("Reading History")
            .toolbar {
                EditButton()
            }
        }
    }
    
    // MARK: - Settings View
    private var settingsView: some View {
        NavigationStack {
            Form {
                if let currentSettings = settings.first {
                    Section(header: Text("Thresholds")) {
                        HStack {
                            Image(systemName: "ear")
                            Text("Sound Threshold")
                            Spacer()
                            Slider(value: Binding(
                                get: { currentSettings.soundThreshold },
                                set: { 
                                    currentSettings.soundThreshold = $0
                                    sensorService.updateSettings(currentSettings)
                                }
                            ), in: 50...100, step: 5)
                            Text("\(Int(currentSettings.soundThreshold)) dB")
                                .frame(width: 50)
                        }
                        
                        HStack {
                            Image(systemName: "lightbulb")
                            Text("Light Threshold")
                            Spacer()
                            Slider(value: Binding(
                                get: { currentSettings.lightThreshold },
                                set: { 
                                    currentSettings.lightThreshold = $0
                                    sensorService.updateSettings(currentSettings)
                                }
                            ), in: 500...2000, step: 100)
                            Text("\(Int(currentSettings.lightThreshold))")
                                .frame(width: 50)
                        }
                        
                        HStack {
                            Image(systemName: "heart")
                            Text("Heart Rate % Increase")
                            Spacer()
                            Slider(value: Binding(
                                get: { currentSettings.heartRateThreshold },
                                set: { 
                                    currentSettings.heartRateThreshold = $0
                                    sensorService.updateSettings(currentSettings)
                                }
                            ), in: 5...50, step: 5)
                            Text("\(Int(currentSettings.heartRateThreshold))%")
                                .frame(width: 50)
                        }
                    }
                    
                    Section(header: Text("Notifications")) {
                        Toggle("Enable Notifications", isOn: Binding(
                            get: { currentSettings.notificationsEnabled },
                            set: { 
                                currentSettings.notificationsEnabled = $0
                                sensorService.updateSettings(currentSettings)
                            }
                        ))
                    }
                    
                    Section(header: Text("Heart Rate Baseline")) {
                        HStack {
                            Text("Current Baseline")
                            Spacer()
                            Text("\(Int(sensorService.baselineHeartRate)) BPM")
                        }
                        
                        Button("Recalibrate") {
                            isCalibrating = true
                        }
                        .disabled(!sensorService.isConnected)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func deleteReadings(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let readingToDelete = readings.sorted { $0.timestamp > $1.timestamp }[index]
                modelContext.delete(readingToDelete)
            }
        }
    }
}

struct SensorReadingView: View {
    let icon: String
    let value: String
    var subvalue: String? = nil
    let thresholdExceeded: Bool
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(thresholdExceeded ? .red : .primary)
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(thresholdExceeded ? .red : .primary)
            
            if let subvalue = subvalue {
                Text(subvalue)
                    .font(.caption)
                    .foregroundColor(thresholdExceeded ? .red : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DeviceListView: View {
    @EnvironmentObject var sensorService: SensorConnectionService
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                if sensorService.devices.isEmpty {
                    Text("Scanning for devices...")
                } else {
                    ForEach(sensorService.devices, id: \.identifier) { device in
                        Button(action: {
                            sensorService.connect(to: device)
                            isPresented = false
                        }) {
                            HStack {
                                Text(device.name ?? "Unknown Device")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Device")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        sensorService.stopScanning()
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
        .environmentObject(SensorConnectionService())
}
