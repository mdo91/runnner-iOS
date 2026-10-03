//
//  DashboardView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Dashboard View
struct DashboardView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @Binding var selectedTab: Int
    @Binding var selectedWorkout: HKWorkout?
    @Binding var showingWorkoutDetail: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Run Analytics")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Text("Track your progress")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Button(action: {
                            if healthKitManager.isAuthorized {
                                healthKitManager.fetchRecentWorkouts()
                            } else {
                                healthKitManager.requestAuthorization()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Quick Stats
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        MetricCard(
                            title: "Total Runs",
                            value: "\(healthKitManager.recentWorkouts.count)",
                            icon: "figure.run",
                            color: .blue
                        )
                        
                        MetricCard(
                            title: "This Week",
                            value: "3",
                            icon: "calendar",
                            color: .green
                        )
                        
                        MetricCard(
                            title: "Avg Pace",
                            value: "5:30",
                            icon: "speedometer",
                            color: .orange
                        )
                        
                        MetricCard(
                            title: "Distance",
                            value: "12.5 km",
                            icon: "location",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                    
                    // Recent Workouts
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Workouts")
                                .font(.headline)
                            Spacer()
                            Button("View All") {
                                selectedTab = 1
                            }
                            .font(.caption)
                        }
                        .padding(.horizontal)
                        
                        ForEach(healthKitManager.recentWorkouts.prefix(3), id: \.uuid) { workout in
                            WorkoutRowView(workout: workout) {
                                selectedWorkout = workout
                                showingWorkoutDetail = true
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    DashboardView(
        healthKitManager: MockData.createMockHealthKitManager(),
        selectedTab: .constant(0),
        selectedWorkout: .constant(nil),
        showingWorkoutDetail: .constant(false)
    )
}
