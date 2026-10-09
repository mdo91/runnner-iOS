import Foundation
import RunCore
import SwiftUI

@MainActor final class TrainingSettings: ObservableObject {
  @Published private(set) var preferences: AnalyticsPreferences
  private let defaults: UserDefaults
  private let key = "trainingAnalytics.v1"
  init(defaults: UserDefaults = AppRuntime.defaults) {
    self.defaults = defaults
    if let data = defaults.data(forKey: key),
      let value = try? JSONDecoder().decode(AnalyticsPreferences.self, from: data),
      value.version == 1
    {
      preferences = value
      if preferences.zones?.isValid == false { preferences.zones = nil }
    } else {
      preferences = AnalyticsPreferences()
    }
  }
  func save(goal: TrainingGoal) {
    guard goal.target.isFinite, goal.target > 0 else { return }
    preferences.goals.removeAll {
      $0.id == goal.id || ($0.metric == goal.metric && $0.period == goal.period)
    }
    preferences.goals.append(goal)
    persist()
  }
  func delete(goal: TrainingGoal) {
    preferences.goals.removeAll { $0.id == goal.id }
    persist()
  }
  func save(zones: HeartRateZones?) {
    guard zones == nil || zones?.isValid == true else { return }
    preferences.zones = zones
    persist()
  }
  func exclude(_ effort: BestEffort) {
    preferences.excludedEfforts.insert(effort.id)
    persist()
  }
  func restoreEfforts() {
    preferences.excludedEfforts = []
    persist()
  }
  func clear() {
    preferences = AnalyticsPreferences()
    defaults.removeObject(forKey: key)
  }
  private func persist() {
    if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
  }
}
