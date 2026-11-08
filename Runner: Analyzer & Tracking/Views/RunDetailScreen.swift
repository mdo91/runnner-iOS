import Charts
import RunCore
import SwiftData
import SwiftUI

struct RunDetailScreen: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var health: HealthKitManager
  @EnvironmentObject private var account: AccountManager
  @EnvironmentObject private var analysis: AnalysisManager
  var row: RecordedRun
  var run: RunData
  var history: [RunData]
  var measurements: [HealthMeasurement]
  var units: UnitSystem
  var latest = false
  @Query private var allRows: [RecordedRun]
  @EnvironmentObject private var analytics: AnalyticsStore
  @State private var selection: Date?
  @State private var selectedSplit: DateInterval?
  @State private var photoSession: RunPhotoSession?
  @State private var pendingPhotoResult: RunPhotoExportResult?
  @State private var photoResult: RunPhotoExportResult?
  @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 42.0
  var body: some View {
    let metrics = analytics.snapshot.metrics[run.id] ?? RunCalculator.metrics(run)
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        DashboardGrid {
          runSummary(metrics)
          routeSection
        }
        DashboardGrid {
          RunCharts(run: run, units: units, selection: $selection)
          splitSection
        }
        RouteComparisons(run: run, rows: allRows, measurements: measurements, units: units)
        assessment(metrics)
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "applewatch")
          Text("RunDetailScreen.Format.importedFromMissingMeasurementsAppearAs.text".localized(String(describing: run.source)))
        }.font(.caption).foregroundStyle(RunnerStyle.muted).padding(.bottom, 20)
        if let status = health.status { Text(status).font(.footnote).foregroundStyle(.orange) }
      }.padding(20).frame(maxWidth: 1200).frame(maxWidth: .infinity)
    }.background(RunnerStyle.background).refreshable { await health.sync() }
      .fullScreenCover(
        item: $photoSession,
        onDismiss: {
          photoResult = pendingPhotoResult
          pendingPhotoResult = nil
        }
      ) { session in
        RunPhotoEditor(run: session.run, units: session.units) { pendingPhotoResult = $0 }
          .environment(\.dynamicTypeSize, typeSize)
      }
      .modifier(RunPhotoExportFeedback(result: $photoResult))
      .onChange(of: selection) { _, date in
        if let interval = selectedSplit,
          date.map({ $0 < interval.start || $0 > interval.end }) ?? true
        {
          selectedSplit = nil
        }
      }
      .navigationTitle(latest ? "Common.Copy.latestRun.text".localized : "Common.Copy.runDetails.text".localized).navigationBarTitleDisplayMode(
        latest ? .large : .inline)
      .modifier(RunnerTabBarStyle())
  }
  private func runSummary(_ metrics: MeasuredMetrics) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        MetricPair {
          Label(run.indoor ? "Common.Copy.iNDOORRUN.text".localized : "Common.Copy.oUTDOORRUN.text".localized, systemImage: "figure.run")
            .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(RunnerStyle.accent)
          if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
          Text(run.start.formatted(.dateTime.month(.abbreviated).day()))
            .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Common.Copy.runSummary.text".localized).font(.subheadline).foregroundStyle(RunnerStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(units.distance(metrics.distanceMeters))
                .font(.system(size: heroSize, weight: .heavy).width(.condensed))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(RunnerStyle.accent)
              Text(units.distanceUnit).font(.headline).foregroundStyle(RunnerStyle.muted)
            }.accessibilityElement(children: .ignore)
              .accessibilityLabel(
                "RunDetailScreen.Format.distance.text".localized(String(describing: units.distance(metrics.distanceMeters)), String(describing: units.distanceUnit))
              )
              .accessibilityIdentifier("run.distance")
          }
          Spacer(minLength: 0)
          Button {
            photoSession = RunPhotoSession(run: run, units: units)
          } label: {
            Image(systemName: "photo.on.rectangle").frame(width: 20, height: 20)
          }.buttonStyle(RunnerSecondaryButtonStyle()).accessibilityLabel("RunDetailScreen.Copy.createRunPhotoOrVideo.text".localized)
            .accessibilityHint("RunDetailScreen.Copy.addYourRunStatsAndRouteToMediaFrom.text".localized)
            .accessibilityIdentifier("run.createPhoto")
        }
        Text(run.start.formatted(.dateTime.weekday(.wide).hour().minute()))
          .font(.caption).foregroundStyle(RunnerStyle.muted)
        MetricGrid {
          MetricTile(
            title: "Common.Copy.movingTime.text".localized, value: UnitSystem.duration(metrics.movingSeconds),
            unit: "RunDetailScreen.Format.elapsed.text".localized(String(describing: UnitSystem.duration(metrics.elapsedSeconds))), symbol: "stopwatch"
          )
          .accessibilityIdentifier("run.movingTime")
          MetricTile(
            title: "Common.Copy.averagePace.text".localized, value: units.pace(metrics.averagePaceSecondsPerKm),
            unit: "RunDetailScreen.Format.min.text".localized(String(describing: units.distanceUnit)), symbol: "speedometer"
          )
          .accessibilityIdentifier("run.averagePace")
          MetricTile(
            title: "Common.Copy.averageHeartRate.text".localized,
            value: metrics.averageHeartRate.map { String(Int($0.rounded())) } ?? "—",
            unit: "Common.Copy.bpm.text".localized, symbol: "heart"
          )
          .accessibilityIdentifier("run.heartRate")
          MetricTile(
            title: "Common.Copy.activeEnergy.text".localized,
            value: metrics.activeEnergyKcal.map { String(Int($0.rounded())) } ?? "—",
            unit: "kcal", symbol: "flame"
          )
          .accessibilityIdentifier("run.energy")
        }
      }
    }.accessibilityElement(children: .contain).accessibilityIdentifier("run.summary")
  }

  @ViewBuilder private var routeSection: some View {
    if !run.route.isEmpty {
      RouteCard(run: run, units: units, selection: $selection, selectedInterval: selectedSplit)
    } else {
      Surface {
        VStack(alignment: .leading, spacing: 8) {
          Label(
            run.indoor ? "RunDetailScreen.Copy.indoorRunRouteNotRecorded.text".localized : "RunDetailScreen.Copy.noGPSRouteAvailable.text".localized,
            systemImage: "map"
          ).font(.headline)
          Text("RunDetailScreen.Copy.yourMeasuredPerformanceIsAvailableWithoutARoute.text".localized)
            .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
      }
    }
  }

  @ViewBuilder private var splitSection: some View {
    let splits = RunCalculator.splits(run, length: units.metersPerUnit)
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        SectionTitle(title: "Common.Copy.splits.text".localized, subtitle: units == .metric ? "Common.Copy.perKilometer.text".localized : "Common.Copy.perMile.text".localized)
        if splits.isEmpty {
          Text("RunDetailScreen.Copy.distanceSamplesArenTAvailableForAccurateSplits.text".localized).font(.subheadline)
            .foregroundStyle(RunnerStyle.muted)
        } else {
          ForEach(splits) { split in
            Button {
              guard let timeline = DistanceTimeline(run),
                let start = timeline.time(
                  at: Double(split.index - 1) * units.metersPerUnit, starting: true),
                let end = timeline.time(
                  at: min(Double(split.index) * units.metersPerUnit, run.distanceMeters ?? 0),
                  starting: false)
              else { return }
              selectedSplit = DateInterval(start: start, end: end)
              selection = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            } label: {
              HStack {
                Text("\(split.index)").frame(width: 24, alignment: .leading).foregroundStyle(
                  RunnerStyle.muted)
                Text(units.pace(split.pace)).font(.headline.monospacedDigit())
                GeometryReader { proxy in
                  RoundedRectangle(cornerRadius: 3).fill(RunnerStyle.accent.opacity(0.75)).frame(
                    width: max(
                      4,
                      proxy.size.width
                        * min(1, (splits.map(\.pace).min() ?? split.pace) / max(1, split.pace))),
                    height: 6
                  ).frame(height: proxy.size.height)
                }.frame(height: 20)
                Text(split.averageHeartRate.map { String(Int($0.rounded())) } ?? "—").font(
                  .subheadline.monospacedDigit()
                ).frame(width: 44, alignment: .trailing)
              }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityLabel(
              "RunDetailScreen.Format.splitMinutesPer.text".localized(String(describing: split.index), String(describing: units.pace(split.pace)), String(describing: units.distanceUnit))
            ).accessibilityIdentifier("run.split.\(split.index)")
          }
          if selectedSplit != nil {
            Text("RunDetailScreen.Copy.selectedSplitHighlightedOnTheRoute.text".localized).accessibilityIdentifier(
              "run.splitSelection"
            ).font(.caption)
            Button("Common.Copy.clearSplit.text".localized) {
              selectedSplit = nil
              selection = nil
            }.buttonStyle(RunnerSecondaryButtonStyle())
          }
        }
      }
    }
  }
  private func assessment(_ metrics: MeasuredMetrics) -> some View {
    Surface {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          SectionTitle(title: "Common.Copy.performance.text".localized, subtitle: "RunDetailScreen.Copy.measuredFirstExplainedClearly.text".localized)
          Spacer()
          Image(systemName: "waveform.path.ecg").foregroundStyle(RunnerStyle.accent)
        }
        if let report = row.report {
          if report.effectiveLanguage != AppLanguage.current {
            Text("RunDetailScreen.Analysis.languageNotice.text".localized)
              .font(.footnote).foregroundStyle(RunnerStyle.muted)
          }
          Text(report.explanation.summary).font(.body).accessibilityIdentifier("run.analysisSummary")
          ForEach(report.explanation.insights) { item in
            VStack(alignment: .leading, spacing: 5) {
              Text(item.title).font(.subheadline.bold())
              Text(item.detail).font(.subheadline).foregroundStyle(RunnerStyle.muted)
              Text("RunDetailScreen.Format.basedOn.text".localized(String(describing: item.evidence.map(evidenceLabel).joined(separator:", ")))).font(
                .caption2
              ).foregroundStyle(RunnerStyle.muted)
            }
          }
          Divider()
          Text("Common.Copy.nextRun.text".localized).font(.subheadline.bold())
          Text(report.explanation.nextRun).font(.subheadline)
          Text(report.endurance.detail).font(.footnote).foregroundStyle(RunnerStyle.muted)
            .accessibilityIdentifier("run.analysisEndurance")
          ForEach(report.missingData, id: \.self) {
            Text($0).font(.caption).foregroundStyle(RunnerStyle.muted)
          }
          Text(
            "RunDetailScreen.Format.aIFitnessCoaching.text".localized(String(describing: report.generatedAt.formatted(date:.abbreviated,time:.shortened)))
          ).font(.caption2).foregroundStyle(RunnerStyle.muted)
        } else {
          if let cv = metrics.pacingCoefficientOfVariation {
            Text("RunDetailScreen.Format.splitPaceVariation.text".localized(String(describing: Int((cv*100).rounded())))).font(.headline)
          }
          Text(
            "RunDetailScreen.Copy.aIAnalysisExplainsYourPaceEffortAndAvailableEndurance.text".localized
          ).font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if account.signedIn && account.consent {
          Button {
            Task {
              await analysis.analyze(
                row, history: history, measurements: measurements, account: account,
                context: context)
            }
          } label: {
            if analysis.working.contains(row.id) {
              ProgressView().frame(maxWidth: .infinity)
            } else {
              Text(row.report.map { $0.effectiveLanguage != AppLanguage.current } == true ? "RunDetailScreen.Analysis.regenerate.text".localized : row.report == nil ? "Common.Copy.analyzeThisRun.text".localized : "Common.Copy.refreshAnalysis.text".localized).frame(
                maxWidth: .infinity)
            }
          }.buttonStyle(RunnerSecondaryButtonStyle()).disabled(analysis.working.contains(row.id))
            .accessibilityIdentifier("run.analyze")
        }
        if let message = analysis.messages[row.id] {
          Text(message).font(.footnote).foregroundStyle(RunnerStyle.muted)
        }
        Text("RunDetailScreen.Copy.fitnessGuidanceForAdultsNotAMedicalAssessment.text".localized).font(.caption2)
          .foregroundStyle(RunnerStyle.muted)
      }
    }
  }
  private func evidenceLabel(_ key: String) -> String {
    switch key {
    case "averagePaceSecondsPerKm": return "Common.Copy.averagePace2.text".localized
    case "averageHeartRate": return "Common.Copy.averageHeartRate2.text".localized
    case "distanceMeters": return "Common.Copy.distance.text".localized
    case "movingSeconds": return "Common.Copy.movingTime2.text".localized
    case "vo2Max": return "Common.Copy.recordedVOMax2.text".localized
    case "maxHeartRate": return "Common.Label.maximumHeartRate.text".localized
    case "heartRateCoverage": return "Common.Label.heartRateCoverage.text".localized
    case "pacingCoefficientOfVariation": return "Common.Label.pacingVariation.text".localized
    case "comparableRunCount": return "Common.Label.comparableRunCount.text".localized
    case "paceChangePercent": return "Common.Label.paceChange.text".localized
    case "previousVo2Max": return "Common.Label.previousVO2.text".localized
    case "recoveryBpm": return "Common.Copy.heartRateRecovery.text".localized
    default: return "Common.Label.measurement.text".localized
    }
  }
  private func dynamicsLabel(_ key: String) -> String {
    switch key {
    case "HKQuantityTypeIdentifierRunningPower": return "Common.Copy.power.text".localized
    case "HKQuantityTypeIdentifierRunningSpeed": return "Common.Copy.speed.text".localized
    case "HKQuantityTypeIdentifierRunningStrideLength": return "Common.Copy.strideLength.text".localized
    case "HKQuantityTypeIdentifierRunningGroundContactTime": return "Common.Copy.groundContact.text".localized
    default: return "Common.Copy.verticalOscillation.text".localized
    }
  }
  private func dynamicsValue(_ key: String, _ value: Double) -> String {
    if key.contains("Power") { return String(format: "%.0f W", locale: Locale.current, value) }
    if key.contains("Speed") { return String(format: "%.1f m/s", locale: Locale.current, value) }
    if key.contains("Contact") { return String(format: "%.0f ms", locale: Locale.current, value * 1000) }
    return String(format: "%.1f cm", locale: Locale.current, value * 100)
  }
}
