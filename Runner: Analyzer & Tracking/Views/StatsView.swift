//
//  StatsView.swift
//  Runner: Analyzer & Tracking
//
//  Created by Mahmoud Aoata on 20/09/2025.
//

import SwiftUI
import Charts
import HealthKit

// MARK: - Supporting Types
enum StatsRange: String, CaseIterable, Identifiable {
    case fourWeeks = "4 W"
    case oneMonth = "1 Month"
    case threeMonths = "3 Months"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .fourWeeks:
            return "Last 4 Weeks"
        case .oneMonth:
            return "Current Month"
        case .threeMonths:
            return "Last 3 Months"
        case .sixMonths:
            return "Last 6 Months"
        case .oneYear:
            return "Last Year"
        }
    }
    
    var usesVerticalLabels: Bool {
        switch self {
        case .threeMonths, .sixMonths, .oneYear:
            return true
        default:
            return false
        }
    }
}

enum StatsMetric: String, CaseIterable, Identifiable {
    case runs
    case distance
    
    var id: String { rawValue }
    
    var headerTitle: String {
        switch self {
        case .runs: return "Runs"
        case .distance: return "Distance (km)"
        }
    }
    
    var menuTitle: String {
        switch self {
        case .runs: return "Show Runs"
        case .distance: return "Show Distance"
        }
    }
    
    var yAxisTitle: String {
        switch self {
        case .runs: return "Runs"
        case .distance: return "Kilometers"
        }
    }
    
    func value(for point: RunStatsPoint) -> Double {
        switch self {
        case .runs: return Double(point.runCount)
        case .distance: return point.totalDistance / 1000.0
        }
    }
    
    func annotationText(for value: Double) -> String {
        switch self {
        case .runs: return "\(Int(value))"
        case .distance: return String(format: "%.1f", value)
        }
    }
    
    func axisLabel(for value: Double) -> String {
        switch self {
        case .runs: return "\(Int(value))"
        case .distance: return String(format: "%.0f", value)
        }
    }
}

struct RunStatsPoint: Identifiable, Equatable {
    let id = UUID()
    let categoryKey: String
    let label: String
    let startDate: Date
    let totalDistance: Double
    let runCount: Int
    
    static func == (lhs: RunStatsPoint, rhs: RunStatsPoint) -> Bool {
        return lhs.categoryKey == rhs.categoryKey &&
        lhs.label == rhs.label &&
        lhs.startDate == rhs.startDate &&
        lhs.totalDistance == rhs.totalDistance &&
        lhs.runCount == rhs.runCount
    }
}

// MARK: - Stats View
struct StatsView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @State private var selectedRange: StatsRange = .fourWeeks
    @State private var primaryMetric: StatsMetric = .runs
    
    private var chartData: [RunStatsPoint] {
        buildStats(for: selectedRange, workouts: healthKitManager.recentWorkouts)
    }
    
    private var totalRuns: Int {
        chartData.reduce(0) { $0 + $1.runCount }
    }
    
    private var totalDistanceMeters: Double {
        chartData.reduce(0) { $0 + $1.totalDistance }
    }
    
    private var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }
    
    private var peakRunCount: Int {
        chartData.map(\.runCount).max() ?? 0
    }
    
    private var peakDistanceKm: Double {
        chartData.map { $0.totalDistance / 1000.0 }.max() ?? 0
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                
                VStack(spacing: 16) {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(StatsRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.all)
                    
                    if chartData.isEmpty {
                        emptyStateView
                    } else {
                        chartView
                        summaryCards
                        distanceChartView
                    }
                    
                    Spacer()
                }
                .navigationTitle("Stats")
                .padding(.top)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
    
    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
//                Text(primaryMetric.headerTitle)
//                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(StatsMetric.allCases) { metric in
                        Button {
                            primaryMetric = metric
                        } label: {
                            if primaryMetric == metric {
                                Label(metric.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(metric.menuTitle)
                            }
                        }
                    }
                } label: {
                    Label(primaryMetric.headerTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal)
            
            Chart(chartData) { point in
                let value = primaryMetric.value(for: point)
                let peakValue = primaryMetric == .runs ? Double(peakRunCount) : peakDistanceKm
                let isPeak = peakValue > 0 && abs(value - peakValue) < 0.001
                
                BarMark(
                    x: .value("Period", point.categoryKey),
                    y: .value(primaryMetric.yAxisTitle, value)
                )
                .foregroundStyle(isPeak ? Color.green : Color.blue.opacity(0.7))
                .annotation(position: .top) {
                    if value > 0 {
                        Text(primaryMetric.annotationText(for: value))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: chartData.map(\.categoryKey)) { value in
                    AxisTick()
                    AxisGridLine()
                    AxisValueLabel {
                        if let key = value.as(String.self),
                           let point = chartData.first(where: { $0.categoryKey == key }) {
                            Text(point.label)
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(selectedRange.usesVerticalLabels ? 90 : 0))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { axisValue in
                    AxisValueLabel {
                        if let val = axisValue.as(Double.self) {
                            Text(primaryMetric.axisLabel(for: val))
                        }
                    }
                }
            }
            .chartXScale(range: .plotDimension(padding: 12))
            .frame(height: 280)
            .padding(.horizontal)
            .animation(.easeInOut(duration: 0.25), value: primaryMetric)
            .animation(.easeInOut(duration: 0.25), value: chartData)
        }
    }
    
    private var summaryCards: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryTile(
                    title: "Total Runs",
                    value: "\(totalRuns)",
                    subtitle: selectedRange.description,
                    icon: "figure.run",
                    tint: .blue
                )
                
                SummaryTile(
                    title: "Distance",
                    value: String(format: "%.1f km", totalDistanceKm),
                    subtitle: "Combined",
                    icon: "map.fill",
                    tint: .purple
                )
            }
            
            if let bestPoint = chartData.max(by: { $0.runCount < $1.runCount }) {
                SummaryTile(
                    title: "Peak Period",
                    value: bestPoint.label,
                    subtitle: "\(bestPoint.runCount) runs • \(String(format: "%.1f km", bestPoint.totalDistance / 1000.0))",
                    icon: "star.fill",
                    tint: .green
                )
            }
        }
        .padding(.horizontal)
    }
    
    private var distanceChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distance (km)")
                .font(.headline)
                .padding(.horizontal)
            
            Chart(chartData) { point in
                LineMark(
                    x: .value("Period", point.categoryKey),
                    y: .value("Distance", point.totalDistance / 1000.0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.purple)
                .lineStyle(.init(lineWidth: 3))
                
                PointMark(
                    x: .value("Period", point.categoryKey),
                    y: .value("Distance", point.totalDistance / 1000.0)
                )
                .symbolSize(40)
                .foregroundStyle(Color.purple)
                .annotation(position: .top) {
                    Text(String(format: "%.1f", point.totalDistance / 1000.0))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: chartData.map(\.categoryKey)) { value in
                    AxisTick()
                    AxisGridLine()
                    AxisValueLabel {
                        if let key = value.as(String.self),
                           let point = chartData.first(where: { $0.categoryKey == key }) {
                            Text(point.label)
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(selectedRange.usesVerticalLabels ? 90 : 0))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let km = value.as(Double.self) {
                            Text(String(format: "%.0f", km))
                        }
                    }
                }
            }
            .frame(height: 220)
            .padding(.horizontal)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No data for \(selectedRange.description)")
                .font(.headline)
            Text("Complete some runs during this period to see your performance analytics.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Summary Tile
private struct SummaryTile: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundColor(tint)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.footnote)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Stats Building Helpers
extension StatsView {
    private func buildStats(for range: StatsRange, workouts: [HKWorkout]) -> [RunStatsPoint] {
        switch range {
        case .fourWeeks:
            return weeklyStats(weeks: 4, referenceDate: Date(), workouts: workouts)
        case .oneMonth:
            return weeklyStatsForCurrentMonth(workouts: workouts)
        case .threeMonths:
            return monthlyStats(months: 3, workouts: workouts)
        case .sixMonths:
            return monthlyStats(months: 6, workouts: workouts)
        case .oneYear:
            return monthlyStats(months: 12, workouts: workouts)
        }
    }
    
    private func weeklyStats(weeks: Int, referenceDate: Date, workouts: [HKWorkout]) -> [RunStatsPoint] {
        let calendar = Calendar.current
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else { return [] }
        
        var data: [RunStatsPoint] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { continue }
            
            let runs = workouts.filter { workout in
                workout.startDate >= weekStart && workout.startDate < weekEnd
            }
            
            let label = Self.weekFormatter.string(from: weekStart)
            data.append(RunStatsPoint(
                categoryKey: Self.weekKeyFormatter.string(from: weekStart),
                label: label,
                startDate: weekStart,
                totalDistance: totalDistance(for: runs),
                runCount: runs.count
            ))
        }
        return data
    }
    
    private func weeklyStatsForCurrentMonth(workouts: [HKWorkout]) -> [RunStatsPoint] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: Date()) else { return [] }
        
        var data: [RunStatsPoint] = []
        var cursor = monthInterval.start
        
        while cursor < monthInterval.end {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: cursor) else { break }
            let weekStart = max(weekInterval.start, monthInterval.start)
            let weekEnd = min(weekInterval.end, monthInterval.end)
            
            if weekStart >= monthInterval.end { break }
            
            let runs = workouts.filter { workout in
                workout.startDate >= weekStart && workout.startDate < weekEnd
            }
            
            let label = Self.weekFormatter.string(from: weekStart)
            data.append(RunStatsPoint(
                categoryKey: Self.weekKeyFormatter.string(from: weekStart),
                label: label,
                startDate: weekStart,
                totalDistance: totalDistance(for: runs),
                runCount: runs.count
            ))
            
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekInterval.start) else { break }
            cursor = nextWeek
        }
        
        return data
    }
    
    private func monthlyStats(months: Int, workouts: [HKWorkout]) -> [RunStatsPoint] {
        let calendar = Calendar.current
        guard let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start else { return [] }
        
        var monthStarts: [Date] = []
        
        if months == 12, let startOfYear = calendar.dateInterval(of: .year, for: Date())?.start {
            for offset in 0..<12 {
                if let monthDate = calendar.date(byAdding: .month, value: offset, to: startOfYear) {
                    monthStarts.append(monthDate)
                }
            }
        } else {
            for offset in stride(from: months - 1, through: 0, by: -1) {
                if let monthDate = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) {
                    monthStarts.append(monthDate)
                }
            }
        }
        
        var data: [RunStatsPoint] = []
        for monthDate in monthStarts {
            guard let monthInterval = calendar.dateInterval(of: .month, for: monthDate) else { continue }
            
            let runs = workouts.filter { workout in
                workout.startDate >= monthInterval.start && workout.startDate < monthInterval.end
            }
            
            let label = Self.monthAbbreviation(for: monthInterval.start)
            data.append(RunStatsPoint(
                categoryKey: Self.monthKeyFormatter.string(from: monthInterval.start),
                label: label,
                startDate: monthInterval.start,
                totalDistance: totalDistance(for: runs),
                runCount: runs.count
            ))
        }
        return data
    }
    
    private func totalDistance(for workouts: [HKWorkout]) -> Double {
        workouts.reduce(0) { partial, workout in
            partial + (workout.totalDistance?.doubleValue(for: .meter()) ?? 0)
        }
    }
    
    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
    
    private static let weekKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-'W'ww"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()
    
    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private static func monthAbbreviation(for date: Date) -> String {
        let month = monthFormatter.string(from: date).uppercased()
        return String(month.prefix(3))
    }
}

#Preview {
    StatsView(healthKitManager: MockData.createMockHealthKitManager())
}

