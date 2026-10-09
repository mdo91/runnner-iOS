import Foundation

/// A validated code, safe to use as a single API path component.
struct DashboardLinkCode: Equatable, Sendable {
  let value: String

  init?(_ input: String) {
    let normalized = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
    guard normalized.count == 10,
      normalized.allSatisfy({ "0123456789ABCDEF".contains($0) })
    else { return nil }
    value = normalized
  }
}

struct DashboardBrowser: Decodable, Equatable, Sendable {
  let agent: String
  let expiresAt: Date

  init(agent: String, expiresAt: Date) {
    self.agent = agent
    self.expiresAt = expiresAt
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    agent = try values.decode(String.self, forKey: .agent)
    let raw = try values.decode(String.self, forKey: .expiresAt)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let expiry = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .expiresAt, in: values,
        debugDescription: "Expected an ISO 8601 browser-link expiry.")
    }
    expiresAt = expiry
  }

  private enum CodingKeys: String, CodingKey { case agent, expiresAt }
}

@MainActor protocol DashboardLinkServicing {
  var dashboardURL: URL? { get }
  func review(code: DashboardLinkCode, userID: String) async throws -> DashboardBrowser
  func approve(code: DashboardLinkCode, userID: String) async throws
}
