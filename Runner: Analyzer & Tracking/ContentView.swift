//
//  ContentView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import HealthKit

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTab = 0
    @State private var showingWorkoutDetail = false
    @State private var selectedWorkout: HKWorkout?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            DashboardView(
                healthKitManager: healthKitManager,
                selectedTab: $selectedTab,
                selectedWorkout: $selectedWorkout,
                showingWorkoutDetail: $showingWorkoutDetail
            )
            .tabItem {
                Image(systemName: "house.fill")
                Text("Dashboard")
            }
            .tag(0)
            
            // Workouts Tab
            WorkoutsView(
                healthKitManager: healthKitManager,
                selectedWorkout: $selectedWorkout,
                showingWorkoutDetail: $showingWorkoutDetail
            )
            .tabItem {
                Image(systemName: "list.bullet")
                Text("Workouts")
            }
            .tag(1)
            
            // Stats Tab
            StatsView(healthKitManager: healthKitManager)
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Stats")
                }
                .tag(2)
            
            // Tracking Tab
            TrackingView(locationManager: locationManager)
                .tabItem {
                    Image(systemName: "location.fill")
                    Text("Track")
                }
                .tag(3)
        }
        .onAppear {
            healthKitManager.requestAuthorization()
            locationManager.requestPermission()
        }
        .sheet(isPresented: $showingWorkoutDetail) {
            if let workout = selectedWorkout {
                WorkoutDetailView(workout: workout)
            }
        }
    }
}


#Preview {
    ContentView()
}

#Preview("With Mock Data") {
    let contentView = ContentView()
    // Note: In a real preview, you'd want to inject mock managers
    // For now, the preview will show the default state
    return contentView
}
