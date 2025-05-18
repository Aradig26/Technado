//
//  ContentView.swift
//  AuSense
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
    @State private var tempSoundThreshold: Double = 85.0
    @State private var tempLightThreshold: Double = 1000.0
    @State private var tempHeartRateThreshold: Double = 20.0
    
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
                // Initialize temp values
                tempSoundThreshold = newSettings.soundThreshold
                tempLightThreshold = newSettings.lightThreshold
                tempHeartRateThreshold = newSettings.heartRateThreshold
            } else {
                sensorService.updateSettings(settings[0])
                // Initialize temp values from existing settings
                if let currentSettings = settings.first {
                    tempSoundThreshold = currentSettings.soundThreshold
                    tempLightThreshold = currentSettings.lightThreshold
                    tempHeartRateThreshold = currentSettings.heartRateThreshold
                }
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
            .navigationTitle("AuSense")
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
                    Section(header: Text("Sound Threshold"), footer: Text("The sound level (in decibels) which may contribute to sensory overload. Normal conversation is around 60dB, and loud environments are 80dB+.")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Current: \(Int(currentSettings.soundThreshold)) dB")
                                    .font(.headline)
                                Spacer()
                                
                                if sensorService.lastReading != nil && sensorService.lastReading!.soundLevel > currentSettings.soundThreshold {
                                    Label("Exceeded", systemImage: "exclamationmark.circle")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            HStack {
                                Text("50 dB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("100 dB")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(
                                value: $tempSoundThreshold,
                                in: 50...100,
                                step: 1
                            ) {
                                Text("Sound Threshold")
                            } minimumValueLabel: {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundColor(.blue)
                            } maximumValueLabel: {
                                Image(systemName: "speaker.wave.3")
                                    .foregroundColor(.red)
                            } onEditingChanged: { editing in
                                if !editing {
                                    currentSettings.soundThreshold = tempSoundThreshold
                                    sensorService.updateSettings(currentSettings)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    tempSoundThreshold = 70
                                    currentSettings.soundThreshold = tempSoundThreshold
                                    sensorService.updateSettings(currentSettings)
                                }) {
                                    Text("Reset to Default (70 dB)")
                                        .font(.caption)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    Section(header: Text("Light Threshold"), footer: Text("The light level (in lux) which may contribute to sensory overload. Indoor lighting is typically 300-500 lux, and bright offices are around 1000 lux.")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Current: \(Int(currentSettings.lightThreshold)) lux")
                                    .font(.headline)
                                Spacer()
                                
                                if sensorService.lastReading != nil && sensorService.lastReading!.lightLevel > currentSettings.lightThreshold {
                                    Label("Exceeded", systemImage: "exclamationmark.circle")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            
                            HStack {
                                Text("500 lux")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("2000 lux")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(
                                value: $tempLightThreshold,
                                in: 500...2000,
                                step: 50
                            ) {
                                Text("Light Threshold")
                            } minimumValueLabel: {
                                Image(systemName: "lightbulb.min")
                                    .foregroundColor(.blue)
                            } maximumValueLabel: {
                                Image(systemName: "lightbulb.max")
                                    .foregroundColor(.red)
                            } onEditingChanged: { editing in
                                if !editing {
                                    currentSettings.lightThreshold = tempLightThreshold
                                    sensorService.updateSettings(currentSettings)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    tempLightThreshold = 1000
                                    currentSettings.lightThreshold = tempLightThreshold
                                    sensorService.updateSettings(currentSettings)
                                }) {
                                    Text("Reset to Default (1000 lux)")
                                        .font(.caption)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    Section(header: Text("Heart Rate Threshold"), footer: Text("The percentage increase in heart rate above your baseline that may indicate stress or discomfort. Baseline is calculated during calibration.")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Current: \(Int(currentSettings.heartRateThreshold))% increase")
                                    .font(.headline)
                                Spacer()
                                
                                if sensorService.lastReading != nil {
                                    let increase = ((sensorService.lastReading!.heartRate - sensorService.baselineHeartRate) / sensorService.baselineHeartRate) * 100
                                    if increase > currentSettings.heartRateThreshold {
                                        Label("Exceeded", systemImage: "exclamationmark.circle")
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                }
                            }
                            
                            HStack {
                                Text("5%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("50%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(
                                value: $tempHeartRateThreshold,
                                in: 5...50,
                                step: 1
                            ) {
                                Text("Heart Rate Threshold")
                            } minimumValueLabel: {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.blue)
                            } maximumValueLabel: {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                            } onEditingChanged: { editing in
                                if !editing {
                                    currentSettings.heartRateThreshold = tempHeartRateThreshold
                                    sensorService.updateSettings(currentSettings)
                                }
                            }
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    tempHeartRateThreshold = 20
                                    currentSettings.heartRateThreshold = tempHeartRateThreshold
                                    sensorService.updateSettings(currentSettings)
                                }) {
                                    Text("Reset to Default (20%)")
                                        .font(.caption)
                                }
                                Spacer()
                            }
                        }
                    }
                    
                    Section(header: Text("Notifications"), footer: Text("When enabeld, youll receive alerts when the app detects a potential sensory overload situation.")) {
                        Toggle("Enable Notifications", isOn: Binding(
                            get: { currentSettings.notificationsEnabled },
                            set: { 
                                currentSettings.notificationsEnabled = $0
                                sensorService.updateSettings(currentSettings)
                            }
                        ))
                    }
                    
                    Section(header: Text("Heart Rate Baseline"), footer: Text("Your baseline heart rate is used to detect increases that may indicate stress or discomfort.")) {
                        HStack {
                            Text("Current Baseline")
                            Spacer()
                            Text("\(Int(sensorService.baselineHeartRate)) BPM")
                                .bold()
                        }
                        
                        Button(action: {
                            isCalibrating = true
                        }) {
                            Label("Recalibrate Baseline", systemImage: "heart.text.square")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .disabled(!sensorService.isConnected)
                        .buttonStyle(.bordered)
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
