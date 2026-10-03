//
//  TotalRunCard.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Total Run Card
struct TotalRunCard: View {
    let totalDistance: Double // in meters
    let period: String
    let runCount: Int
    
    private var totalKm: Double {
        return totalDistance / 1000.0
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Run in KM")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(period)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("🏃‍♂️")
                    .font(.system(size: 32))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.2f", totalKm))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("kilometers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(runCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    
                    Text("runs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}

#Preview {
    VStack(spacing: 16) {
        TotalRunCard(
            totalDistance: 25000, // 25 km
            period: "This Week",
            runCount: 3
        )
        
        TotalRunCard(
            totalDistance: 85000, // 85 km
            period: "This Month",
            runCount: 12
        )
        
        TotalRunCard(
            totalDistance: 450000, // 450 km
            period: "This Year",
            runCount: 48
        )
    }
    .padding()
}

