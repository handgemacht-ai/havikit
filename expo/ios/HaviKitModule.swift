import ExpoModulesCore
import Foundation
import HaviKit

/// The JS `start(config)` argument, mapped 1:1 from the `HaviConfig` TS type
/// (which mirrors the stamped `HAVI_*` keys). Optional values arrive as `nil`.
internal struct HaviStartConfig: Record {
  @Field var enabled: Bool = false
  @Field var baseUrl: String = ""
  @Field var workspaceId: String?
  @Field var project: String?
  @Field var worktree: String?
  @Field var branch: String?
  @Field var commit: String?
  @Field var imageFormat: String?
  @Field var devToken: String?

  init() {}
}

/// Thrown when the SDK is enabled without a usable base URL. Surfaces as a
/// rejected JS promise — the catchable counterpart of `HaviConfig.fromBundle`'s
/// `fatalError`, so a misconfiguration never hard-crashes the RN runtime.
internal final class HaviInvalidBaseURLException: Exception {
  override var reason: String {
    "HaviKit is enabled but config.baseUrl is missing or invalid — pass a valid HAVI_BASE_URL."
  }
}

/// Builds the immutable `HaviConfig` from the JS payload. Enabled-without-a-valid
/// URL throws (rejecting `start`); a disabled config resolves to the inert path.
/// Called from `start`, which hops to `.main`, so this runs on the main thread.
private func makeHaviConfig(from config: HaviStartConfig) throws -> HaviConfig {
  let trimmed = config.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
  let url = trimmed.isEmpty ? nil : URL(string: trimmed)
  if config.enabled && url == nil {
    throw HaviInvalidBaseURLException()
  }
  let format = HaviImageFormat(rawValue: (config.imageFormat ?? "png").lowercased()) ?? .png
  return HaviConfig(
    isEnabled: config.enabled,
    baseURL: url,
    workspaceID: config.workspaceId,
    project: config.project,
    worktree: config.worktree,
    branch: config.branch,
    commit: config.commit,
    imageFormat: format,
    devToken: config.devToken,
    redaction: HaviRedactionPolicy()
  )
}

public class HaviKitModule: Module {
  public func definition() -> ModuleDefinition {
    Name("HaviKit")

    AsyncFunction("start") { (config: HaviStartConfig) throws in
      let resolved = try makeHaviConfig(from: config)
      MainActor.assumeIsolated {
        Havi.start(config: resolved)
      }
    }
    .runOnQueue(.main)

    Function("capture") { (screen: String?) in
      Havi.triggerCapture(screen: screen)
    }

    Function("log") { (message: String, level: String?, category: String?) in
      Havi.log(
        message,
        level: HaviLogLevel(rawValue: (level ?? "info").lowercased()) ?? .info,
        category: category ?? "app"
      )
    }

    Function("logNetworkError") { (message: String) in
      Havi.logNetworkError(message)
    }

    Function("setContext") { (namespace: String, values: [String: String]) in
      Havi.setContext(namespace, values)
    }

    Function("setTag") { (key: String, value: String) in
      Havi.setTag(key, value)
    }

    Function("setScreen") { (name: String?) in
      Havi.setScreen(name)
    }

    Function("setPriority") { (priority: String?) in
      MainActor.assumeIsolated {
        Havi.setPriority(priority.flatMap { HaviPriority(rawValue: $0.lowercased()) })
      }
    }
    .runOnQueue(.main)

    Function("signIn") { (token: String, workspaceId: String) in
      MainActor.assumeIsolated {
        Havi.signIn(token: token, workspaceID: workspaceId)
      }
    }
    .runOnQueue(.main)

    Function("disconnect") {
      MainActor.assumeIsolated {
        Havi.disconnect()
      }
    }
    .runOnQueue(.main)

    Function("signOut") {
      MainActor.assumeIsolated {
        Havi.signOut()
      }
    }
    .runOnQueue(.main)

    AsyncFunction("getAuthState") { () -> [String: String] in
      MainActor.assumeIsolated {
        switch Havi.authState {
        case .unconfigured:
          return ["status": "unconfigured"]
        case let .authenticated(workspaceID):
          return ["status": "authenticated", "workspaceId": workspaceID]
        case .needsReconnect:
          return ["status": "needsReconnect"]
        }
      }
    }
    .runOnQueue(.main)

    Function("getIsEnabled") { () -> Bool in
      Havi.isEnabled
    }

    View(HaviOverlayView.self) {}
  }
}
