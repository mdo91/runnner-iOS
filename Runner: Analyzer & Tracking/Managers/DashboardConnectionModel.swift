import Combine
import Foundation

@MainActor final class DashboardConnectionModel: ObservableObject {
  struct Review: Equatable {
    let code: DashboardLinkCode
    let userID: String
    let browser: DashboardBrowser
  }

  enum State: Equatable {
    case idle, reviewing
    case reviewed(Review)
    case approving(Review)
    case approved
  }

  @Published var code = "" {
    didSet { if code != oldValue { reset() } }
  }
  @Published private(set) var state: State = .idle
  @Published private(set) var message: String?
  private let service: any DashboardLinkServicing
  private let now: () -> Date
  private var userID: String?
  private var generation = 0

  init(service: any DashboardLinkServicing, now: @escaping () -> Date = Date.init) {
    self.service = service
    self.now = now
  }

  var dashboardURL: URL? { service.dashboardURL }
  var isWorking: Bool {
    switch state {
    case .reviewing, .approving: return true
    default: return false
    }
  }
  var canReview: Bool { userID != nil && DashboardLinkCode(code) != nil && !isWorking }
  var browser: DashboardBrowser? {
    switch state {
    case .reviewed(let review), .approving(let review): return review.browser
    default: return nil
    }
  }

  func selectAccount(_ userID: String?) {
    guard self.userID != userID else { return }
    self.userID = userID
    reset()
  }

  /// Invalidates responses after edits, dismissal, or an account change, including A→B→A edits.
  func reset() {
    generation += 1
    state = .idle
    message = nil
  }

  func review() async {
    guard canReview, let userID, let requested = DashboardLinkCode(code) else { return }
    generation += 1
    let requestGeneration = generation
    state = .reviewing
    message = nil
    do {
      let browser = try await service.review(code: requested, userID: userID)
      guard generation == requestGeneration else { return }
      guard !Task.isCancelled else {
        reset()
        return
      }
      guard browser.expiresAt > now() else {
        expireReview()
        return
      }
      state = .reviewed(Review(code: requested, userID: userID, browser: browser))
    } catch {
      guard generation == requestGeneration else { return }
      state = .idle
      if !Task.isCancelled {
        message =
          "This code could not be reviewed. Check your connection or request a new code in the browser."
      }
    }
  }

  func approve() async {
    guard case .reviewed(let review) = state, review.userID == userID,
      review.code == DashboardLinkCode(code)
    else { return }
    guard review.browser.expiresAt > now() else {
      expireReview()
      return
    }
    let requestGeneration = generation
    state = .approving(review)
    message = nil
    do {
      try await service.approve(code: review.code, userID: review.userID)
      guard generation == requestGeneration else { return }
      guard !Task.isCancelled else {
        reset()
        return
      }
      state = .approved
    } catch {
      guard generation == requestGeneration else { return }
      guard !Task.isCancelled else {
        reset()
        return
      }
      guard review.browser.expiresAt > now() else {
        expireReview()
        return
      }
      state = .reviewed(review)
      message = "Approval could not finish. Check your connection or request a new code."
    }
  }

  private func expireReview() {
    state = .idle
    message = "This code has expired. Request a new code in the browser."
  }
}
