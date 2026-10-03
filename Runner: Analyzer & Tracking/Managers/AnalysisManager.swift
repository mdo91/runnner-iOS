import CryptoKit
import FirebaseAppCheck
import FirebaseAuth
import Foundation
import RunCore
import SwiftData

struct APIClient {
  static var baseURL: URL? {
    guard let path = Bundle.main.path(forResource: "ServiceConfig", ofType: "plist"),
      let values = NSDictionary(contentsOfFile: path), let raw = values["API_BASE_URL"] as? String,
      let url = URL(string: raw), url.scheme == "https"
    else { return nil }
    return url
  }
  static func request(path: String, method: String, body: Data? = nil) async throws -> Data {
    guard let baseURL, let user = Auth.auth().currentUser else { throw APIError.notReady }
    let identity = try await user.getIDToken()
    let attestation = try await AppCheck.appCheck().token(forcingRefresh: false)
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 35
    request.setValue("Bearer \(identity)", forHTTPHeaderField: "Authorization")
    request.setValue(attestation.token, forHTTPHeaderField: "X-Firebase-AppCheck")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw APIError.unavailable }
    guard (200...299).contains(http.statusCode) else {
      if http.statusCode == 429 { throw APIError.quota }
      if http.statusCode == 409 { throw APIError.pending }
      if http.statusCode == 401 { throw APIError.authentication }
      throw APIError.unavailable
    }
    return data
  }
  static func deleteAccount() async throws {
    _ = try await request(path: "v1/account", method: "DELETE")
  }
  static func analyze(_ input: AnalysisRequest, live: Bool = false) async throws -> AnalysisReport {
    let data = try await request(
      path: live ? "v1/live/analyze" : "v1/runs/analyze", method: "POST", body: encode(input))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
        return date
      }
      throw APIError.invalidResponse
    }
    let report = try decoder.decode(AnalysisReport.self, from: data)
    guard report.schemaVersion == 1, report.id == input.id, report.status == "complete",
      report.metrics == input.metrics
    else { throw APIError.invalidResponse }
    if live {
      guard let expiry = report.expiresAt, expiry > Date(),
        Date().timeIntervalSince(report.generatedAt) < 90
      else { throw APIError.invalidResponse }
    }
    return report
  }
  static func encode(_ input: AnalysisRequest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(input)
  }
  enum APIError: LocalizedError {
    case notReady, quota, pending, authentication, unavailable, invalidResponse
    var errorDescription: String? {
      switch self {
      case .notReady: return "Sign in and enable AI analysis in Settings."
      case .quota:
        return "Today's analysis limit has been reached. Your measured stats remain available."
      case .pending: return "This run is already being analyzed. Try again shortly."
      case .authentication: return "Please sign in again to use AI analysis."
      case .unavailable:
        return "Analysis is temporarily unavailable. Your measured stats remain available."
      case .invalidResponse:
        return "The analysis could not be verified. Your measured stats remain available."
      }
    }
  }
}
@MainActor final class AnalysisManager: ObservableObject {
  @Published var working: Set<UUID> = []
  @Published var messages: [UUID: String] = [:]
  func analyze(
    _ row: RecordedRun, history: [RunData], measurements: [HealthMeasurement],
    account: AccountManager, context: ModelContext, automatic: Bool = false
  ) async {
    guard account.signedIn, account.consent, account.adultConfirmed, let run = row.run,
      !working.contains(row.id)
    else { return }
    let request = AnalysisRequest(
      run: run, history: history,
      vo2: measurements.filter { $0.kind == "HKQuantityTypeIdentifierVO2Max" }.map(\.measurement),
      recovery: measurements.filter {
        $0.kind == "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute"
      }.map(\.measurement))
    do {
      let hash = SHA256.hash(data: try APIClient.encode(request)).map { String(format: "%02x", $0) }
        .joined()
      if row.reportInputHash == hash { return }
      if automatic, let attempted = row.lastAnalysisAttempt,
        Date().timeIntervalSince(attempted) < 300
      {
        return
      }
      working.insert(row.id)
      defer { working.remove(row.id) }
      row.lastAnalysisAttempt = Date()
      try context.save()
      let uid = Auth.auth().currentUser?.uid
      let report = try await APIClient.analyze(request)
      guard account.consent, account.signedIn, row.modelContext != nil,
        Auth.auth().currentUser?.uid == uid
      else { return }
      guard let latest = row.run, RunRevision.hasSameAnalysisData(run, latest) else { return }
      row.reportData = try JSONEncoder().encode(report)
      row.reportInputHash = hash
      try context.save()
      messages[row.id] = nil
    } catch {
      messages[row.id] =
        (error as? APIClient.APIError)?.errorDescription
        ?? "You appear to be offline. Your measured stats remain available."
    }
  }
}
