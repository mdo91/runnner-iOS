import Foundation
import RunCore

enum ReleaseLinks {
  static let root = URL(string: "https://mdo91.github.io/runnner-iOS/")!
  static var website: URL { root.appendingPathComponent(AppLanguage.current.rawValue + "/") }
  static var privacy: URL { website.appendingPathComponent("privacy/") }
  static var support: URL { website.appendingPathComponent("support/") }
  static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
