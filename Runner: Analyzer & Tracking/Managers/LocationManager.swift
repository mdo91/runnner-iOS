//
//  LocationManager.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import Foundation
import CoreLocation

// MARK: - Location Manager
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var route: [CLLocation] = []
    @Published var isTracking = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5 // 5 meters
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        guard locationManager.authorizationStatus == .authorizedWhenInUse else { return }
        locationManager.startUpdatingLocation()
        isTracking = true
        route.removeAll()
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        route.append(location)
    }
}

