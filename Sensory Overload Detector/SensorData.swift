//
//  SensorData.swift
//  AuSense
//
//  Created for AuSense
//

import Foundation
import SwiftData

@Model
final class SensorReading {
    var timestamp: Date
    var soundLevel: Double // in decibels
    var lightLevel: Double // in lux
    var heartRate: Double  // in BPM
    var isOverload: Bool   // indicates if this reading triggered an overload warning
    
    init(timestamp: Date = Date(), soundLevel: Double = 0, lightLevel: Double = 0, heartRate: Double = 0, isOverload: Bool = false) {
        self.timestamp = timestamp
        self.soundLevel = soundLevel
        self.lightLevel = lightLevel
        self.heartRate = heartRate
        self.isOverload = isOverload
    }
}

@Model
final class UserSettings {
    var soundThreshold: Double // in decibels
    var lightThreshold: Double // in lux
    var heartRateThreshold: Double // increase % that indicates stress
    var notificationsEnabled: Bool
    
    init(soundThreshold: Double = 85.0, lightThreshold: Double = 1000.0, heartRateThreshold: Double = 20.0, notificationsEnabled: Bool = true) {
        self.soundThreshold = soundThreshold
        self.lightThreshold = lightThreshold
        self.heartRateThreshold = heartRateThreshold
        self.notificationsEnabled = notificationsEnabled
    }
} 
