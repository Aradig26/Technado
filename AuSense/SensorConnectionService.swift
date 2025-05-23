import Foundation
import CoreBluetooth
import UserNotifications

class SensorConnectionService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // MARK: - Properties
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var lastReading: SensorReading?
    @Published var devices: [CBPeripheral] = []
    
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    // ESP32 Service and Characteristics UUIDs (example - replace with actual UUIDs from your ESP32)
    private let espServiceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    private let soundCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")
    private let lightCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A9")
    private let heartRateCharacteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26AA")
    
    private var userSettings: UserSettings?
    private var notificationManager = NotificationManager()
    
    var baselineHeartRate: Double = 70.0 // Resting heart rate, can be calibrated
    
    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
        setupNotifications()
    }
    
    private func setupNotifications() {
        notificationManager.requestPermission()
    }
    
    // MARK: - Public Methods
    func startScanning() {
        print(centralManager.state == .poweredOn)
        isScanning = true
        devices.removeAll()
        if centralManager.state == .poweredOn {
          centralManager.scanForPeripherals(withServices: [espServiceUUID], options: nil)
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
        stopScanning()
    }
    
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
      DispatchQueue.main.async {
        if central.state == .poweredOn {
          if self.isScanning {
            central.scanForPeripherals(withServices: [self.espServiceUUID], options: nil)
          }
        } else {
          // reset your flags
          self.isScanning = false
          self.isConnected = false
        }
      }
    }

    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !devices.contains(peripheral) {
            devices.append(peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
      central.stopScan()
      peripheral.discoverServices([espServiceUUID])
      DispatchQueue.main.async {
        self.isScanning = false
        self.isConnected = true
      }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
      DispatchQueue.main.async {
        self.isConnected = false
        self.isScanning = false
      }
      self.peripheral = nil
    }

    
    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            // Subscribe to notifications for all sensor characteristics
            if [soundCharacteristicUUID, lightCharacteristicUUID, heartRateCharacteristicUUID].contains(characteristic.uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let _ = userSettings else { return }
        
        // Create a new reading if we don't have one
        if lastReading == nil {
            lastReading = SensorReading()
        }
        
        // Update the appropriate sensor value
        if characteristic.uuid == soundCharacteristicUUID {
            let soundLevel = Double(data.withUnsafeBytes { $0.load(as: Float.self) })
            lastReading?.soundLevel = soundLevel
        } else if characteristic.uuid == lightCharacteristicUUID {
            let lightLevel = Double(data.withUnsafeBytes { $0.load(as: Float.self) })
            lastReading?.lightLevel = lightLevel
        } else if characteristic.uuid == heartRateCharacteristicUUID {
            let heartRate = Double(data.withUnsafeBytes { $0.load(as: UInt8.self) })
            lastReading?.heartRate = heartRate
        }
        
        // Check for sensory overload
        checkForSensoryOverload()
    }
    
    // MARK: - Helper Methods
    private func checkForSensoryOverload() {
        guard let reading = lastReading, let settings = userSettings else { return }
        
        // Check if any thresholds are exceeded
        let isSoundExceeded = reading.soundLevel > settings.soundThreshold
        let isLightExceeded = reading.lightLevel > settings.lightThreshold
        
        // Calculate heart rate increase percentage
        let heartRateIncrease = ((reading.heartRate - baselineHeartRate) / baselineHeartRate) * 100
        let isHeartRateExceeded = heartRateIncrease > settings.heartRateThreshold
        
        // Determine if this is an overload situation
        let isOverload = (isSoundExceeded && isLightExceeded) || 
                         (isSoundExceeded && isHeartRateExceeded) || 
                         (isLightExceeded && isHeartRateExceeded)
        
        reading.isOverload = isOverload
        
        // Send notification if there's an overload and notifications are enabled
        if isOverload && settings.notificationsEnabled {
            var triggers = [String]()
            if isSoundExceeded { triggers.append("high sound levels") }
            if isLightExceeded { triggers.append("bright lighting") }
            if isHeartRateExceeded { triggers.append("elevated heart rate") }
            
            let triggersText = triggers.joined(separator: ", ")
            notificationManager.sendOverloadNotification(triggers: triggersText)
        }
    }
    
    func updateSettings(_ newSettings: UserSettings) {
        self.userSettings = newSettings
    }
    
    func calibrateHeartRate(with rate: Double) {
        self.baselineHeartRate = rate
    }
}
