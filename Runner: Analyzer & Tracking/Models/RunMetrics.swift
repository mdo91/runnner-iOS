//
//  RunMetrics.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import Foundation
import CoreLocation

// MARK: - Data Models
struct RunMetrics {
    let duration: TimeInterval
    let distance: Double // in meters
    let averagePace: Double // in seconds per meter
    let calories: Double
    let averageHeartRate: Double?
    let route: [CLLocation]?
    let timestamp: Date
    
    // MARK: - Computed Properties
    var distanceInKilometers: Double {
        return distance / 1000.0
    }
    
    var formattedDistance: String {
        return String(format: "%.2f km", distanceInKilometers)
    }
    
    var averagePacePerKm: Double {
        return averagePace * 1000.0 // Convert to seconds per kilometer
    }
    
    var formattedPace: String {
        let totalSeconds = Int(averagePacePerKm)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
