//
//  NotificationManager.swift
//  Sensory Overload Detector
//
//  Created for Sensory Overload Detector
//

import Foundation
import UserNotifications

class NotificationManager {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    func sendOverloadNotification(triggers: String) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Sensory Overload Warning"
        content.body = "Environment may cause sensory overload. Detected: \(triggers)"
        content.sound = UNNotificationSound.defaultCritical
        
        // Schedule immediate notification
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate delivery
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
} 