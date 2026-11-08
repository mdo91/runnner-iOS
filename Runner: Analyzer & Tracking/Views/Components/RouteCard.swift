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
  var selectedInterval: DateInterval? = nil
  @State private var mode = "Common.Copy.pace.text".localized
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
        if mode == "Common.Copy.heartRate.text".localized {
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
      hue: mode == "Common.Copy.pace.text".localized ? 0.58 - t * 0.17 : 0.58 - t * 0.55, saturation: 0.75, brightness: 0.95)
  }
  var body: some View {
    let chunks = chunks
    let values = chunks.compactMap(\.value)
    let range = (values.min() ?? 0)...(values.max() ?? 1)
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Common.Copy.yourRoute.text".localized,
          subtitle: "RouteCard.Format.alongTheRunGPSSharingIsOptionalIn.text".localized(String(describing: mode)))
        Picker("Common.Copy.routeColor.text".localized, selection: $mode) {
          Text("Common.Copy.pace.text".localized).tag("Common.Copy.pace.text".localized)
          Text("Common.Copy.heartRate.text".localized).tag("Common.Copy.heartRate.text".localized)
        }.pickerStyle(.segmented)
        MapReader { proxy in
          Map(initialPosition: .automatic) {
            ForEach(chunks) { chunk in
              MapPolyline(
                coordinates: chunk.points.map {
                  CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
              ).stroke(
                selectedInterval.map { interval in
                  chunk.points.contains {
                    $0.timestamp >= interval.start && $0.timestamp <= interval.end
                  }
                } == true ? RunnerStyle.accent : color(chunk.value, range: range),
                style: StrokeStyle(
                  lineWidth: selectedInterval == nil ? 5 : 7, lineCap: .round, lineJoin: .round))
            }
            if let point = segments.first?.first {
              Annotation(
                "Common.Copy.start.text".localized,
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
                "Common.Copy.finish.text".localized,
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
              }), abs(point.timestamp.timeIntervalSince(selection)) <= 20,
              !run.pauses.contains(where: { selection >= $0.start && selection < $0.end })
            {
              Annotation(
                "Common.Copy.selected.text".localized,
                coordinate: CLLocationCoordinate2D(
                  latitude: point.latitude, longitude: point.longitude)
              ) {
                Circle().fill(.white).frame(width: 14, height: 14).overlay(
                  Circle().stroke(RunnerStyle.accent, lineWidth: 3))
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
        }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel(
          "RouteCard.Format.routeMapColoredByWithStartAndFinish.text".localized(String(describing: mode.lowercased())))
        if values.isEmpty {
          Text("RouteCard.Format.noSynchronizedMeasurements.text".localized(String(describing: mode.lowercased()))).font(.caption).foregroundStyle(
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
          "RouteCard.Copy.gapsMarkPausesOrUnavailableGPSRouteColorsDescribe.text".localized
        ).font(.caption2).foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func label(_ value: Double) -> String {
    mode == "Common.Copy.pace.text".localized ? "\(units.pace(value)) /\(units.distanceUnit)" : "RouteCard.Format.bpm.text".localized(String(describing: Int(value)))
  }
}
struct DensityMap: View {
  var runs: [RunData]
  @State private var days = 30
  private var cells: [DensityCell] {
    RouteDensity.cells(
      runs: runs.filter { $0.start > AppRuntime.now.addingTimeInterval(-Double(days) * 86400) })
  }
  var body: some View {
    let cells = cells
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        SectionTitle(
          title: "RouteCard.Copy.placesYouReturnTo.text".localized, subtitle: "RouteCard.Copy.routeDensityOneVisitPerRunPerArea.text".localized)
        Picker("Common.Copy.dateRange.text".localized, selection: $days) {
          Text("Common.Copy.1Month.text".localized).tag(30)
          Text("Common.Copy.3Months.text".localized).tag(90)
          Text("Common.Copy.1Year.text".localized).tag(365)
        }.pickerStyle(.segmented)
        if cells.isEmpty {
          Text("RouteCard.Copy.outdoorRunsWithGPSWillBuildYourMapHere.text".localized).font(.subheadline)
            .foregroundStyle(RunnerStyle.muted).padding(.vertical, 30)
        } else {
          Map(initialPosition: .automatic) {
            ForEach(Array(cells.prefix(5000))) { cell in
              MapCircle(
                center: CLLocationCoordinate2D(latitude: cell.latitude, longitude: cell.longitude),
                radius: 45
              ).foregroundStyle(
                RunnerStyle.accent.opacity(
                  min(0.85, 0.15 + Double(cell.runs) / Double(cells.first?.runs ?? 1) * 0.65)))
            }
          }.mapStyle(.standard(pointsOfInterest: .excludingAll)).frame(height: 250).clipShape(
            RoundedRectangle(cornerRadius: 16))
          Text("RouteCard.Copy.lighterBlueFewerRunsBrighterBlueMoreRuns.text".localized).font(.caption)
            .foregroundStyle(RunnerStyle.muted)
        }
      }
    }
  }
}
