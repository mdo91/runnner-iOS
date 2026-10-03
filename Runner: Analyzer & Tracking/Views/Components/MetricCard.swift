//
//  MetricCard.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI

// MARK: - Metric Card View
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            MetricCard(
                title: "Total Runs",
                value: "12",
                icon: "figure.run",
                color: .blue
            )
            
            MetricCard(
                title: "This Week",
                value: "3",
                icon: "calendar",
                color: .green
            )
        }
        
        HStack(spacing: 16) {
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
    }
    .padding()
}
