import Foundation
import RunCore

/// Owns the wire contract and delegates authenticated transport to the shared API client.
@MainActor struct DashboardLinkService: DashboardLinkServicing {
  var dashboardURL: URL? {
    guard let url = APIClient.baseURL?.appendingPathComponent("dashboard"),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    components.queryItems = [URLQueryItem(name: "lang", value: AppLanguage.current.rawValue)]
    return components.url
  }

  func review(code: DashboardLinkCode, userID: String) async throws -> DashboardBrowser {
    let data = try await APIClient.request(
      path: "v1/dashboard/link/\(code.value)", method: "GET", expectedUID: userID)
    return try JSONDecoder().decode(DashboardBrowser.self, from: data)
  }

  func approve(code: DashboardLinkCode, userID: String) async throws {
    _ = try await APIClient.request(
      path: "v1/dashboard/approve", method: "POST",
      body: APIClient.encode(["code": code.value]), expectedUID: userID)
  }
}
