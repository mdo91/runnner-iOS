//
//  HealthKitManager.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import Foundation
import HealthKit

// MARK: - HealthKit Manager
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    @Published var recentWorkouts: [HKWorkout] = []
    
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.fetchRecentWorkouts()
                }
            }
        }
    }
    
    func fetchRecentWorkouts() {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 100, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            DispatchQueue.main.async {
                self?.recentWorkouts = samples as? [HKWorkout] ?? []
            }
        }
        healthStore.execute(query)
    }
}

