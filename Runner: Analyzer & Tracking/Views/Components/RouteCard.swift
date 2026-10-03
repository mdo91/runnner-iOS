import MapKit
import RunCore
import SwiftUI

private struct ColoredRoute: Identifiable {
  var id: Int
  var points: [RoutePoint]
  var value: Double?
}
struct RouteCard: View {
  var run: RunData
  var units: UnitSystem
  @Binding var selection: Date?
  @State private var mode = "Pace"
  private var segments: [[RoutePoint]] { RunCalculator.routeSegments(run) }
  private var chunks: [ColoredRoute] {
    var result: [ColoredRoute] = []
    for segment in segments {
      let step = max(1, segment.count / 150)
      for start in stride(from: 0, to: segment.count - 1, by: step) {
        let end = min(start + step, segment.count - 1)
        let points = Array(segment[start...end])
        let a = segment[start]
        let b = segment[end]
        let value: Double?
        if mode == "Heart rate" {
          let closest = run.heartRate.min {
            abs($0.start.timeIntervalSince(a.timestamp))
              < abs($1.start.timeIntervalSince(a.timestamp))
          }
          value = closest.flatMap {
            abs($0.start.timeIntervalSince(a.timestamp)) <= 30 ? $0.value : nil
          }
        } else {
          let distance = zip(points, points.dropFirst()).reduce(0) {
            $0 + RunCalculator.distance($1.0, $1.1)
          }
          value = distance > 1 ? b.timestamp.timeIntervalSince(a.timestamp) / distance * 1000 : nil
        }
        result.append(ColoredRoute(id: result.count, points: points, value: value))
      }
    }
    return result
  }
  private func color(_ value: Double?, range: ClosedRange<Double>) -> Color {
    guard let value else { return .gray }
    let t = (value - range.lowerBound) / max(1, range.upperBound - range.lowerBound)
    return Color(
      hue: mode == "Pace" ? 0.58 - t * 0.17 : 0.58 - t * 0.55, saturation: 0.75, brightness: 0.95)
  }
  var body: some View {
    let chunks = chunks
    let values = chunks.compactMap(\.value)
    let range = (values.min() ?? 0)...(values.max() ?? 1)
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Your route", subtitle: "\(mode) along the run · GPS stays on this device")
        Picker("Route color", selection: $mode) {
          Text("Pace").tag("Pace")
          Text("Heart rate").tag("Heart rate")
        }.pickerStyle(.segmented)
        MapReader { proxy in
          Map(initialPosition: .automatic) {
            ForEach(chunks) { chunk in
              MapPolyline(
                coordinates: chunk.points.map {
                  CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
              ).stroke(
                color(chunk.value, range: range),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let point = segments.first?.first {
              Annotation(
                "Start",
                coordinate: CLLocationCoordinate2D(
                  latitude: point.latitude, longitude: point.longitude)
              ) {
                Image(systemName: "play.fill").font(.caption2).padding(8).background(
                  .blue, in: Circle()
                ).overlay(Circle().stroke(.white, lineWidth: 2))
              }
            }
            if let point = segments.last?.last {
              Annotation(
                "Finish",
                coordinate: CLLocationCoordinate2D(
                  latitude: point.latitude, longitude: point.longitude)
              ) {
                Image(systemName: "flag.checkered").font(.caption).padding(8).background(
                  .black, in: Circle()
                ).overlay(Circle().stroke(.white, lineWidth: 2))
              }
            }
            if let selection,
              let point = segments.flatMap({ $0 }).min(by: {
                abs($0.timestamp.timeIntervalSince(selection))
                  < abs($1.timestamp.timeIntervalSince(selection))
              })
            {
              Annotation(
                "Selected",
                coordinate: CLLocationCoordinate2D(
                  latitude: point.latitude, longitude: point.longitude)
              ) {
                Circle().fill(.white).frame(width: 14, height: 14).overlay(
                  Circle().stroke(RunnerStyle.blue, lineWidth: 3))
              }
            }
          }.mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll)).mapControls {
            MapCompass()
          }
          .onTapGesture { position in
            if let coordinate = proxy.convert(position, from: .local) {
              let point = RoutePoint(
                timestamp: Date(), latitude: coordinate.latitude, longitude: coordinate.longitude)
              selection =
                segments.flatMap { $0 }.min {
                  RunCalculator.distance($0, point) < RunCalculator.distance($1, point)
                }?.timestamp
            }
          }
        }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel(
          "Route map colored by \(mode.lowercased()), with start and finish markers")
        if values.isEmpty {
          Text("No synchronized \(mode.lowercased()) measurements.").font(.caption).foregroundStyle(
            RunnerStyle.muted)
        } else {
          HStack {
            Text(label(range.lowerBound))
            LinearGradient(
              colors: [
                color(range.lowerBound, range: range), color(range.upperBound, range: range),
              ], startPoint: .leading, endPoint: .trailing
            ).frame(height: 5).clipShape(Capsule())
            Text(label(range.upperBound))
          }.font(.caption.monospacedDigit()).foregroundStyle(RunnerStyle.muted)
        }
        Text(
          "Gaps mark pauses or unavailable GPS. Route colors describe measurements, not target zones."
        ).font(.caption2).foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func label(_ value: Double) -> String {
    mode == "Pace" ? "\(units.pace(value)) /\(units.distanceUnit)" : "\(Int(value)) bpm"
  }
}
struct DensityMap: View {
  var runs: [RunData]
  @State private var days = 30
  private var cells: [DensityCell] {
    RouteDensity.cells(
      runs: runs.filter { $0.start > Date().addingTimeInterval(-Double(days) * 86400) })
  }
  var body: some View {
    let cells = cells
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        SectionTitle(
          title: "Places you return to", subtitle: "Route density · one visit per run, per area")
        Picker("Date range", selection: $days) {
          Text("1 month").tag(30)
          Text("3 months").tag(90)
          Text("1 year").tag(365)
        }.pickerStyle(.segmented)
        if cells.isEmpty {
          Text("Outdoor runs with GPS will build your map here.").font(.subheadline)
            .foregroundStyle(RunnerStyle.muted).padding(.vertical, 30)
        } else {
          Map(initialPosition: .automatic) {
            ForEach(Array(cells.prefix(5000))) { cell in
              MapCircle(
                center: CLLocationCoordinate2D(latitude: cell.latitude, longitude: cell.longitude),
                radius: 45
              ).foregroundStyle(
                RunnerStyle.blue.opacity(
                  min(0.85, 0.15 + Double(cell.runs) / Double(cells.first?.runs ?? 1) * 0.65)))
            }
          }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 250).clipShape(
            RoundedRectangle(cornerRadius: 16))
          Text("Lighter blue: fewer runs · Brighter blue: more runs").font(.caption)
            .foregroundStyle(RunnerStyle.muted)
        }
      }
    }
  }
}
