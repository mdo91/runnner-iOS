//
//  MockData.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import Foundation
import HealthKit
import CoreLocation

// MARK: - Mock Data for Previews
class MockData {
    
    // MARK: - Mock HealthKit Workouts
    static func createMockWorkouts() -> [HKWorkout] {
        let calendar = Calendar.current
        let now = Date()
        
        var workouts: [HKWorkout] = []
        
        // CURRENT MONTH RUNS (September 2025)
        
        // Workout 1 - Today (10km run)
        let workout1 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .hour, value: -2, to: now)!,
            end: calendar.date(byAdding: .hour, value: -1, to: now)!,
            duration: 3600, // 1 hour
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 450),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 10000), // 10.00 km
            metadata: nil
        )
        workouts.append(workout1)
        
        // Workout 2 - Yesterday (7.5km run)
        let workout2 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -1, to: now)!,
            end: calendar.date(byAdding: .day, value: -1, to: calendar.date(byAdding: .minute, value: 45, to: now)!)!,
            duration: 2700, // 45 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 320),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 7500), // 7.50 km
            metadata: nil
        )
        workouts.append(workout2)
        
        // Workout 3 - 3 days ago (5km run)
        let workout3 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -3, to: now)!,
            end: calendar.date(byAdding: .day, value: -3, to: calendar.date(byAdding: .minute, value: 30, to: now)!)!,
            duration: 1800, // 30 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 280),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 5000), // 5.00 km
            metadata: nil
        )
        workouts.append(workout3)
        
        // Workout 4 - 1 week ago (12km run)
        let workout4 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -7, to: now)!,
            end: calendar.date(byAdding: .day, value: -7, to: calendar.date(byAdding: .hour, value: 1, to: calendar.date(byAdding: .minute, value: 15, to: now)!)!)!,
            duration: 4500, // 1 hour 15 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 520),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 12000), // 12.00 km
            metadata: nil
        )
        workouts.append(workout4)
        
        // Workout 5 - 2 weeks ago (3.2km run)
        let workout5 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -14, to: now)!,
            end: calendar.date(byAdding: .day, value: -14, to: calendar.date(byAdding: .minute, value: 20, to: now)!)!,
            duration: 1200, // 20 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 180),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 3200), // 3.20 km
            metadata: nil
        )
        workouts.append(workout5)
        
        // Workout 6 - 2 days ago (8km run)
        let workout6 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -2, to: now)!,
            end: calendar.date(byAdding: .day, value: -2, to: calendar.date(byAdding: .minute, value: 50, to: now)!)!,
            duration: 3000, // 50 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 380),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 8000), // 8.00 km
            metadata: nil
        )
        workouts.append(workout6)
        
        // Workout 7 - 4 days ago (6km run)
        let workout7 = HKWorkout(
            activityType: .running,
            start: calendar.date(byAdding: .day, value: -4, to: now)!,
            end: calendar.date(byAdding: .day, value: -4, to: calendar.date(byAdding: .minute, value: 35, to: now)!)!,
            duration: 2100, // 35 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 290),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 6000), // 6.00 km
            metadata: nil
        )
        workouts.append(workout7)
        
        // Workout 8 - Early September (15km run)
        let earlySeptember = calendar.date(bySetting: .day, value: 5, of: now)!
        let workout8 = HKWorkout(
            activityType: .running,
            start: earlySeptember,
            end: calendar.date(byAdding: .hour, value: 1, to: calendar.date(byAdding: .minute, value: 30, to: earlySeptember)!)!,
            duration: 5400, // 1 hour 30 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 650),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 15000), // 15.00 km
            metadata: nil
        )
        workouts.append(workout8)
        
        // PREVIOUS MONTHS RUNS (August 2025)
        
        // Workout 9 - August 15th (21km run - Half Marathon)
        let august15 = calendar.date(bySetting: .month, value: 8, of: calendar.date(bySetting: .day, value: 15, of: now)!)!
        let workout9 = HKWorkout(
            activityType: .running,
            start: august15,
            end: calendar.date(byAdding: .hour, value: 2, to: calendar.date(byAdding: .minute, value: 15, to: august15)!)!,
            duration: 8100, // 2 hours 15 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 850),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 21000), // 21.00 km
            metadata: nil
        )
        workouts.append(workout9)
        
        // Workout 10 - August 10th (8.5km run)
        let august10 = calendar.date(bySetting: .month, value: 8, of: calendar.date(bySetting: .day, value: 10, of: now)!)!
        let workout10 = HKWorkout(
            activityType: .running,
            start: august10,
            end: calendar.date(byAdding: .minute, value: 45, to: august10)!,
            duration: 2700, // 45 minutes
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 340),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 8500), // 8.50 km
            metadata: nil
        )
        workouts.append(workout10)
        
        // PREVIOUS YEAR RUNS (2024)
        
        // Workout 11 - December 2024 (10km run)
        let december2024 = calendar.date(bySetting: .year, value: 2024, of: calendar.date(bySetting: .month, value: 12, of: calendar.date(bySetting: .day, value: 20, of: now)!)!)!
        let workout11 = HKWorkout(
            activityType: .running,
            start: december2024,
            end: calendar.date(byAdding: .hour, value: 1, to: december2024)!,
            duration: 3600, // 1 hour
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 450),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 10000), // 10.00 km
            metadata: nil
        )
        workouts.append(workout11)
        
        return workouts
    }
    
    // MARK: - Mock GPS Route
    static func createMockRoute() -> [CLLocation] {
        let baseLocation = CLLocation(latitude: 37.7749, longitude: -122.4194) // San Francisco
        var route: [CLLocation] = []
        
        // Create a simple running route
        for i in 0..<20 {
            let latOffset = Double(i) * 0.001 // Small increments
            let lonOffset = Double(i) * 0.0005
            let location = CLLocation(
                latitude: baseLocation.coordinate.latitude + latOffset,
                longitude: baseLocation.coordinate.longitude + lonOffset
            )
            route.append(location)
        }
        
        return route
    }
    
    // MARK: - Mock Location Manager
    static func createMockLocationManager() -> LocationManager {
        let manager = LocationManager()
        manager.route = createMockRoute()
        manager.isTracking = true
        return manager
    }
    
    // MARK: - Mock HealthKit Manager
    static func createMockHealthKitManager() -> HealthKitManager {
        let manager = HealthKitManager()
        manager.isAuthorized = true
        manager.recentWorkouts = createMockWorkouts()
        return manager
    }
    
    // MARK: - Helper Functions
    static func metersToKilometers(_ meters: Double) -> Double {
        return meters / 1000.0
    }
    
    static func kilometersToMeters(_ kilometers: Double) -> Double {
        return kilometers * 1000.0
    }
    
    static func formatDistanceInKm(_ meters: Double) -> String {
        let km = metersToKilometers(meters)
        return String(format: "%.2f km", km)
    }
    
    static func calculatePacePerKm(duration: TimeInterval, distanceInMeters: Double) -> String {
        let distanceInKm = metersToKilometers(distanceInMeters)
        guard distanceInKm > 0 else { return "N/A" }
        
        let paceSecondsPerKm = duration / distanceInKm
        let minutes = Int(paceSecondsPerKm) / 60
        let seconds = Int(paceSecondsPerKm) % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Date Filtering Functions
    static func filterWorkoutsForWeek(_ workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
        
        return workouts.filter { workout in
            workout.startDate >= weekAgo
        }
    }
    
    static func filterWorkoutsForMonth(_ workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get the start and end of the current month
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let endOfMonth = calendar.dateInterval(of: .month, for: now)?.end ?? now
        
        return workouts.filter { workout in
            workout.startDate >= startOfMonth && workout.startDate < endOfMonth
        }
    }
    
    static func filterWorkoutsForYear(_ workouts: [HKWorkout]) -> [HKWorkout] {
        let calendar = Calendar.current
        let now = Date()
        
        // Get the start and end of the current year
        let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let endOfYear = calendar.dateInterval(of: .year, for: now)?.end ?? now
        
        return workouts.filter { workout in
            workout.startDate >= startOfYear && workout.startDate < endOfYear
        }
    }
    
    static func calculateTotalDistance(_ workouts: [HKWorkout]) -> Double {
        return workouts.reduce(0) { total, workout in
            total + (workout.totalDistance?.doubleValue(for: .meter()) ?? 0)
        }
    }
    
    static func getPeriodString(for period: WorkoutPeriod) -> String {
        switch period {
        case .week:
            return "This Week"
        case .month:
            return "This Month"
        case .year:
            return "This Year"
        }
    }
}

// MARK: - Workout Period Enum
enum WorkoutPeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
}
