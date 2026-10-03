//
//  WorkoutDetailView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Workout Detail View
struct WorkoutDetailView: View {
    let workout: HKWorkout
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text(workout.startDate, style: .date)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Running Workout")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    
                    // Metrics Grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        MetricCard(
                            title: "Duration",
                            value: formatDuration(workout.duration),
                            icon: "clock",
                            color: .blue
                        )
                        
                        MetricCard(
                            title: "Distance",
                            value: "\(String(format: "%.2f", (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000)) km",
                            icon: "location",
                            color: .green
                        )
                        
                        MetricCard(
                            title: "Calories",
                            value: "\(String(format: "%.0f", workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0))",
                            icon: "flame",
                            color: .orange
                        )
                        
                        MetricCard(
                            title: "Avg Pace",
                            value: calculatePace(),
                            icon: "speedometer",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func calculatePace() -> String {
        guard let distance = workout.totalDistance?.doubleValue(for: .meter()),
              distance > 0 else { return "N/A" }
        
        let distanceInKm = distance / 1000.0
        let paceSecondsPerKm = workout.duration / distanceInKm
        let minutes = Int(paceSecondsPerKm) / 60
        let seconds = Int(paceSecondsPerKm) % 60
        
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    WorkoutDetailView(workout: MockData.createMockWorkouts().first!)
}
