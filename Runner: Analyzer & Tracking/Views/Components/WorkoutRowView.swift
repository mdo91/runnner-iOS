//
//  WorkoutRowView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Workout Row View
struct WorkoutRowView: View {
    let workout: HKWorkout
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.startDate, style: .date)
                        .font(.headline)
                    Text("Duration: \(formatDuration(workout.duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(String(format: "%.2f", (workout.totalDistance?.doubleValue(for: .meter()) ?? 0) / 1000)) km")
                        .font(.headline)
                    Text("\(String(format: "%.0f", workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0)) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
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
}

#Preview {
    List {
        ForEach(MockData.createMockWorkouts().prefix(3), id: \.uuid) { workout in
            WorkoutRowView(workout: workout) {
                print("Tapped workout")
            }
        }
    }
}
