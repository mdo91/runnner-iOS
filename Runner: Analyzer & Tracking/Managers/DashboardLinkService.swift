import Foundation

/// Owns the wire contract and delegates authenticated transport to the shared API client.
@MainActor struct DashboardLinkService: DashboardLinkServicing {
  var dashboardURL: URL? { APIClient.baseURL?.appendingPathComponent("dashboard") }

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
