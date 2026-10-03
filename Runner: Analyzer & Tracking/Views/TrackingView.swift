//
//  TrackingView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import CoreLocation

// MARK: - Tracking View
struct TrackingView: View {
    @ObservedObject var locationManager: LocationManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if locationManager.isTracking {
                    VStack {
                        Text("Tracking in Progress")
                            .font(.headline)
                        Text("Distance: \(String(format: "%.2f", calculateDistanceInKm(from: locationManager.route))) km")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Button("Stop Tracking") {
                            locationManager.stopTracking()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                    
                    if !locationManager.route.isEmpty {
                        RunMapView(route: locationManager.route)
                            .frame(height: 300)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Start a Run")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Track your run with GPS")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button("Start Tracking") {
                            locationManager.requestPermission()
                            locationManager.startTracking()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                }
            }
            .navigationTitle("Tracking")
        }
    }
    
    private func calculateDistanceInKm(from locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var totalDistance: Double = 0
        for i in 1..<locations.count {
            totalDistance += locations[i].distance(from: locations[i-1])
        }
        return totalDistance / 1000.0 // Convert to kilometers
    }
}

#Preview("Tracking Active") {
    TrackingView(locationManager: MockData.createMockLocationManager())
}

#Preview("Not Tracking") {
    let manager = LocationManager()
    manager.isTracking = false
    return TrackingView(locationManager: manager)
}
