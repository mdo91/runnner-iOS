import RunCore
import SwiftUI
import UIKit

enum RunnerStyle {
  static let background = Color(red: 11 / 255, green: 11 / 255, blue: 11 / 255)
  static let surface = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
  static let elevated = Color(red: 36 / 255, green: 36 / 255, blue: 36 / 255)
  static let primary = Color.white
  static let muted = Color(red: 184 / 255, green: 184 / 255, blue: 184 / 255)
  static let accent = Color(red: 215 / 255, green: 1, blue: 0)
  static let border = Color.white.opacity(0.14)
  static let cornerRadius: CGFloat = 18
  static func metricFont(_ style: Font.TextStyle = .title2) -> Font {
    .system(style, weight: .heavy).width(.condensed)
  }
  static func configureNativeAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithOpaqueBackground()
    appearance.backgroundColor = UIColor(background)
    for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
      appearance.compactInlineLayoutAppearance]
    {
      item.normal.iconColor = UIColor(muted)
      item.normal.titleTextAttributes = [.foregroundColor: UIColor(muted)]
      item.selected.iconColor = UIColor(accent)
      item.selected.titleTextAttributes = [.foregroundColor: UIColor(accent)]
    }
    UITabBar.appearance().standardAppearance = appearance
    UITabBar.appearance().scrollEdgeAppearance = appearance
  }
}

struct RunnerTabBarStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(RunnerTabBarBackdrop().frame(width: 0, height: 0).accessibilityHidden(true))
      .toolbarBackground(RunnerStyle.background, for: .tabBar)
      .toolbarBackground(.visible, for: .tabBar)
      .toolbarColorScheme(.dark, for: .tabBar)
  }
}

/// Keep chart and map colors from washing out the native floating tab bar.
private struct RunnerTabBarBackdrop: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> Controller { Controller() }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.installBackdrop()
  }
  final class Controller: UIViewController {
    private final class Backdrop: UIView {}
    override func viewDidLoad() {
      super.viewDidLoad()
      view.backgroundColor = .clear
      view.isUserInteractionEnabled = false
    }
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      installBackdrop()
    }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      installBackdrop()
    }
    func installBackdrop() {
      guard let bar = tabBarController?.tabBar, let container = bar.superview else { return }
      bar.unselectedItemTintColor = UIColor(RunnerStyle.muted)
      bar.tintColor = UIColor(RunnerStyle.accent)
      // Preserve readable symbol colors when Liquid Glass adapts to nearby charts.
      for item in bar.items ?? [] {
        if let icon = item.image, icon.renderingMode != .alwaysOriginal {
          let selected = item.selectedImage ?? icon
          item.image = icon.withTintColor(UIColor(RunnerStyle.muted), renderingMode: .alwaysOriginal)
          item.selectedImage = selected.withTintColor(
            UIColor(RunnerStyle.accent), renderingMode: .alwaysOriginal)
        }
      }
      guard !container.subviews.contains(where: { $0 is Backdrop }) else { return }
      let backdrop = Backdrop()
      backdrop.backgroundColor = UIColor(RunnerStyle.background)
      backdrop.isUserInteractionEnabled = false
      backdrop.accessibilityElementsHidden = true
      backdrop.translatesAutoresizingMaskIntoConstraints = false
      container.insertSubview(backdrop, belowSubview: bar)
      NSLayoutConstraint.activate([
        backdrop.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
        backdrop.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
        backdrop.topAnchor.constraint(equalTo: bar.topAnchor),
        backdrop.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
      ])
    }
  }
}

struct Surface<Content: View>: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(RunnerStyle.surface, in: RoundedRectangle(cornerRadius: RunnerStyle.cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: RunnerStyle.cornerRadius)
          .stroke(contrast == .increased ? .white.opacity(0.45) : RunnerStyle.border, lineWidth: 1)
      }
  }
}

struct Stat: View {
  var title: String
  var value: String
  var unit: String
  var symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(title, systemImage: symbol).font(.subheadline)
        .fixedSize(horizontal: false, vertical: true).foregroundStyle(RunnerStyle.muted)
      Text(value).font(RunnerStyle.metricFont()).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(RunnerStyle.primary)
      Text(unit).font(.caption).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(RunnerStyle.muted)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .ignore).accessibilityLabel("\(title), \(value) \(unit)")
  }
}

struct MetricTile: View {
  var title: String
  var value: String
  var unit: String
  var symbol: String
  var body: some View {
    Stat(title: title, value: value, unit: unit, symbol: symbol)
      .padding(16).frame(
        maxWidth: .infinity, minHeight: 108, maxHeight: .infinity, alignment: .topLeading
      )
      .background(RunnerStyle.elevated, in: RoundedRectangle(cornerRadius: 14))
      .overlay { RoundedRectangle(cornerRadius: 14).stroke(RunnerStyle.border, lineWidth: 1) }
  }
}

/// Measures the container, so iPad split views reflow like compact iPhones.
private struct RunnerGridLayout: Layout {
  let breakpoint: CGFloat
  let compactColumns: Int
  let wideColumns: Int
  let singleColumn: Bool
  private let spacing: CGFloat = 12
  private func columns(_ width: CGFloat) -> Int {
    if singleColumn || width < 300 { return 1 }
    return width >= breakpoint ? wideColumns : compactColumns
  }
  private func measurements(width: CGFloat, subviews: Subviews) -> (Int, CGFloat, [CGFloat]) {
    let count = columns(width)
    let cell = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
    var heights: [CGFloat] = []
    for index in subviews.indices {
      let row = index / count
      if row == heights.count { heights.append(0) }
      heights[row] = max(
        heights[row], subviews[index].sizeThatFits(.init(width: cell, height: nil)).height)
    }
    return (count, cell, heights)
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = max(1, proposal.width ?? 360)
    let (_, _, heights) = measurements(width: width, subviews: subviews)
    return CGSize(
      width: width, height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let (count, cell, heights) = measurements(width: bounds.width, subviews: subviews)
    var y = bounds.minY
    for index in subviews.indices {
      let row = index / count
      let column = index % count
      if column == 0 && row > 0 { y += heights[row - 1] + spacing }
      subviews[index].place(
        at: CGPoint(x: bounds.minX + CGFloat(column) * (cell + spacing), y: y),
        anchor: .topLeading, proposal: .init(width: cell, height: heights[row]))
    }
  }
}

struct MetricGrid<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var content: Content
  var body: some View {
    RunnerGridLayout(
      breakpoint: 720, compactColumns: 2, wideColumns: 4,
      singleColumn: typeSize.isAccessibilitySize
    ) { content }
  }
}

struct DashboardGrid<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @ViewBuilder var content: Content
  var body: some View {
    RunnerGridLayout(
      breakpoint: 840, compactColumns: 1, wideColumns: 2,
      singleColumn: typeSize.isAccessibilitySize
    ) { content }
  }
}

struct RunnerPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline).padding(.horizontal, 16).padding(.vertical, 12)
      .frame(minHeight: 44).foregroundStyle(.black)
      .background(RunnerStyle.accent, in: RoundedRectangle(cornerRadius: 14))
      .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
  }
}

struct RunnerSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.subheadline.weight(.semibold))
      .padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
      .foregroundStyle(RunnerStyle.accent)
      .background(RunnerStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
      .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
  }
}

struct EmptyState: View {
  var symbol: String
  var title: String
  var detail: String
  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: symbol).font(.system(size: 42, weight: .medium))
        .foregroundStyle(RunnerStyle.accent).accessibilityHidden(true)
      Text(title).font(.title2.bold())
      Text(detail).font(.body).foregroundStyle(RunnerStyle.muted).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
  }
}

struct SectionTitle: View {
  var title: String
  var subtitle: String? = nil
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
      if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(RunnerStyle.muted) }
    }.fixedSize(horizontal: false, vertical: true)
  }
}

struct RunListRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @EnvironmentObject private var analytics: AnalyticsStore
  var run: RunData
  var units: UnitSystem
  var body: some View {
    let m = analytics.snapshot.metrics[run.id] ?? RunCalculator.metrics(run)
    Surface {
      MetricPair {
        Image(systemName: run.indoor ? "figure.run.treadmill" : "figure.run").font(.title2)
          .foregroundStyle(RunnerStyle.accent).frame(width: 44, height: 48)
          .background(RunnerStyle.elevated, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(run.start.formatted(date: .abbreviated, time: .omitted)).font(.headline)
          Text(
            "\(UnitSystem.duration(m.movingSeconds)) · \(units.pace(m.averagePaceSecondsPerKm)) /\(units.distanceUnit)"
          )
          .font(.subheadline).foregroundStyle(RunnerStyle.muted)
        }
        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
          Text(units.distance(m.distanceMeters)).font(RunnerStyle.metricFont(.title3))
            .monospacedDigit().foregroundStyle(RunnerStyle.accent)
          Text(units.distanceUnit).font(.caption).foregroundStyle(RunnerStyle.muted)
        }
      }
    }.contentShape(Rectangle()).accessibilityElement(children: .combine)
  }
}

struct MetricPair<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var size
  @ViewBuilder var content: Content
  var body: some View {
    let layout =
      size.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    layout { content }
  }
}

struct ScreenLayout<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.frame(maxWidth: 1200, alignment: .leading).frame(maxWidth: .infinity)
  }
}
