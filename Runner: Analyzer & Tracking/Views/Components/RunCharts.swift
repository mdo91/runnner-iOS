import Charts
import RunCore
import SwiftUI

struct RunCharts: View {
  var run: RunData
  var units: UnitSystem
  @Binding var selection: Date?
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var series: [RunSeriesMetric: RunSeries] = [:]
  @State private var metric: RunSeriesMetric = .pace
  @State private var distanceAxis = false
  @State private var selectedX: Double?
  @State private var explore = false
  private var current: RunSeries? { series[metric] }
  private func x(_ point: RunSeriesPoint) -> Double {
    distanceAxis ? (point.distanceMeters ?? 0) / units.metersPerUnit : point.elapsedSeconds / 60
  }
  private func y(_ point: RunSeriesPoint) -> Double {
    switch metric {
    case .pace: return point.value * units.metersPerUnit / 1000 / 60
    case .elevation: return point.value / units.metersPerElevationUnit
    default: return point.value
    }
  }
  private var unit: String {
    switch metric {
    case .pace: return "RunCharts.Format.min.text".localized(String(describing: units.distanceUnit))
    case .heartRate: return "Common.Copy.bpm.text".localized
    case .elevation: return units.elevationUnit
    case .power: return "W"
    case .stride: return "m"
    case .groundContact: return "ms"
    case .verticalOscillation: return "cm"
    }
  }
  private func summary(_ point: RunSeriesPoint) -> String {
    let value =
      metric == .pace
      ? units.pace(point.value)
      : y(point).formatted(.number.precision(.fractionLength(metric == .stride ? 2 : 1)))
    return "RunCharts.Format.elapsed.text".localized(String(describing: UnitSystem.duration(point.elapsedSeconds)), String(describing: value), String(describing: unit))
  }
  var body: some View {
    Surface {
      VStack(alignment: .leading, spacing: 14) {
        SectionTitle(
          title: "Common.Copy.exploreYourRun.text".localized,
          subtitle: "RunCharts.Copy.chartPointsSplitsAndRouteMarkersShareTheSame.text".localized)
        Picker("Common.Copy.measurement.text".localized, selection: $metric) {
          ForEach(RunSeriesMetric.allCases, id: \.self) { Text($0.title).tag($0) }
        }.accessibilityIdentifier("run.metric")
        if let current, !current.points.isEmpty {
          if current.supportsDistanceAxis {
            Picker("Common.Copy.chartAxis.text".localized, selection: $distanceAxis) {
              Text("Common.Copy.elapsedTime.text".localized).tag(false)
              Text("Common.Copy.distance.text".localized).tag(true)
            }.pickerStyle(.segmented)
          } else {
            Text("RunCharts.Copy.distanceAxisUnavailableWithoutValidatedDistanceIntervals.text".localized).font(.caption)
              .foregroundStyle(RunnerStyle.muted)
          }
          Chart {
            ForEach(current.points) { point in
              LineMark(
                x: .value(distanceAxis ? units.distanceUnit : "Common.Copy.elapsedMinutes.text".localized, x(point)),
                y: .value(metric.title, y(point)),
                series: .value("Common.Copy.recordingSegment.text".localized, point.segment)
              ).foregroundStyle(RunnerStyle.accent)
            }
            if let selection, let point = nearest(to: selection, in: current) {
              RuleMark(x: .value("Common.Copy.selection.text".localized, x(point))).foregroundStyle(RunnerStyle.muted)
              PointMark(x: .value("Common.Copy.selected.text".localized, x(point)), y: .value(metric.title, y(point)))
                .foregroundStyle(RunnerStyle.accent)
            }
          }.chartXSelection(value: $selectedX).chartYAxisLabel(unit).chartXAxisLabel(
            distanceAxis ? units.distanceUnit : "Common.Copy.elapsedMinutes.text".localized
          )
          .chartYScale(domain: .automatic(reversed: metric == .pace)).frame(height: 190)
          Text(current.source).font(.caption).foregroundStyle(RunnerStyle.muted)
          if let selection {
            Text(
              nearest(to: selection, in: current).map(summary)
                ?? "RunCharts.Copy.noMeasurementAtThisTimePauseOrRecordingGap.text".localized
            )
            .font(.subheadline.monospacedDigit()).accessibilityIdentifier("run.selection")
          }
          Button("Common.Copy.exploreSamples.text".localized) { explore = true }
            .buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("run.samples")
          if selection != nil {
            Button("Common.Copy.clearSelection.text".localized) {
              selection = nil
              selectedX = nil
            }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityIdentifier("run.clearSelection")
          }
        } else {
          Text("RunCharts.Format.noRecordedAvailable.text".localized(String(describing: metric.title.lowercased()))).accessibilityIdentifier(
            "run.unavailable"
          ).foregroundStyle(RunnerStyle.muted)
        }
      }
    }.task(id: run.importedAt) { series = await analytics.service.series(run: run) }
      .onChange(of: metric) { _, _ in
        selectedX = nil
        if current?.supportsDistanceAxis != true { distanceAxis = false }
      }
      .onChange(of: distanceAxis) { _, _ in selectedX = nil }
      .onChange(of: selectedX) { _, value in
        guard let value, let current,
          let point = current.points.min(by: { abs(x($0) - value) < abs(x($1) - value) }),
          abs(x(point) - value) <= (distanceAxis ? 0.1 : 0.5)
        else { return }
        selection = run.start.addingTimeInterval(point.elapsedSeconds)
      }
      .sheet(isPresented: $explore) {
        NavigationStack {
          List(current?.points ?? []) { point in
            Button(summary(point)) {
              selection = run.start.addingTimeInterval(point.elapsedSeconds)
              explore = false
            }.accessibilityIdentifier("run.sample.\(point.id)")
          }.navigationTitle(metric.title).toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Common.Copy.done.text".localized) { explore = false } }
          }
        }
      }
  }
  private func nearest(to date: Date, in series: RunSeries) -> RunSeriesPoint? {
    let seconds = date.timeIntervalSince(run.start)
    guard !run.pauses.contains(where: { date >= $0.start && date < $0.end }),
      let point = series.points.min(by: {
        abs($0.elapsedSeconds - seconds) < abs($1.elapsedSeconds - seconds)
      }), abs(point.elapsedSeconds - seconds) <= (metric == .elevation ? 20 : 30)
    else { return nil }
    return point
  }
}
