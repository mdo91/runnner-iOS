//
//  RunMapView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Map Annotation Model
struct RoutePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Map View
struct RunMapView: View {
    let route: [CLLocation]
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    private var routePoints: [RoutePoint] {
        route.map { RoutePoint(coordinate: $0.coordinate) }
    }
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: routePoints) { point in
            MapAnnotation(coordinate: point.coordinate) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
        }
        .onAppear {
            if let firstLocation = route.first {
                region.center = firstLocation.coordinate
            }
        }
    }
}

#Preview {
    RunMapView(route: MockData.createMockRoute())
        .frame(height: 300)
        .cornerRadius(12)
        .padding()
}
