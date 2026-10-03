//
//  WorkoutsView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Workouts View
struct WorkoutsView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var selectedWorkout: HKWorkout?
    @Binding var showingWorkoutDetail: Bool
    @State private var selectedPeriod: WorkoutPeriod = .week
    
    private var filteredWorkouts: [HKWorkout] {
        switch selectedPeriod {
        case .week:
            return MockData.filterWorkoutsForWeek(healthKitManager.recentWorkouts)
        case .month:
            return MockData.filterWorkoutsForMonth(healthKitManager.recentWorkouts)
        case .year:
            return MockData.filterWorkoutsForYear(healthKitManager.recentWorkouts)
        }
    }
    
    private var totalDistance: Double {
        return MockData.calculateTotalDistance(filteredWorkouts)
    }
    
    private var periodString: String {
        return MockData.getPeriodString(for: selectedPeriod)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Control
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(WorkoutPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Total Run Card
                        TotalRunCard(
                            totalDistance: totalDistance,
                            period: periodString,
                            runCount: filteredWorkouts.count
                        )
                        .padding(.horizontal)
                        
                        // Workouts List
                        if filteredWorkouts.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "figure.run")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                Text("No runs found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Text("Start tracking your runs to see them here")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.top, 50)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(filteredWorkouts, id: \.uuid) { workout in
                                    WorkoutRowView(workout: workout) {
                                        selectedWorkout = workout
                                        showingWorkoutDetail = true
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Workouts")
            .refreshable {
                healthKitManager.fetchRecentWorkouts()
            }
        }
    }
}

#Preview {
    WorkoutsView(
        healthKitManager: MockData.createMockHealthKitManager(),
        selectedWorkout: .constant(nil),
        showingWorkoutDetail: .constant(false)
    )
}
