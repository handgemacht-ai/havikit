import Foundation

/// Integer size in **points** (logical), used for `target.state`'s
/// `viewport=WxH` value (design §3).
public struct HaviSize: Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Integer rectangle in **downscaled image-pixel** space, matching the
/// screenshot the coordinates are drawn against (design §3, §4).
public struct HaviRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The `x:havi.dev` scoping block. `project` / `worktree` / `branch` are the
/// load-bearing triage axes (also sent as multipart siblings); `commit` rides in
/// `x:havi.dev` only. Each field is omitted from the envelope when nil.
public struct HaviDev: Sendable, Equatable {
    public var project: String?
    public var worktree: String?
    public var branch: String?
    public var commit: String?

    public init(project: String? = nil, worktree: String? = nil, branch: String? = nil, commit: String? = nil) {
        self.project = project
        self.worktree = worktree
        self.branch = branch
        self.commit = commit
    }
}

/// Everything the envelope builder needs to assemble one annotation (design §3).
/// SDK-4 populates it at capture time; the builder is a pure function over it.
public struct HaviEnvelopeInput: Sendable {
    public var bundleID: String
    public var screen: String
    public var viewport: HaviSize
    /// The `FragmentSelector` region in image pixels — the markup rectangle or,
    /// when there is no markup, the full frame.
    public var fragment: HaviRect
    /// The drawn rectangle in image pixels. When present it produces the
    /// `SvgSelector`; when nil, no `SvgSelector` is emitted (design §3).
    public var markup: HaviRect?
    /// Display-only `CssSelector` value: `"<screen> > <a11y-id path>"`.
    public var cssPath: String
    public var comment: String?
    public var priority: HaviPriority?
    public var deviceInfo: String?
    public var appLogs: String?
    public var dev: HaviDev
    public var contexts: [String: [String: String]]
    public var tags: [String: String]
    public var strokeColor: String
    public var strokeWidth: Int

    public init(
        bundleID: String,
        screen: String,
        viewport: HaviSize,
        fragment: HaviRect,
        markup: HaviRect? = nil,
        cssPath: String,
        comment: String? = nil,
        priority: HaviPriority? = nil,
        deviceInfo: String? = nil,
        appLogs: String? = nil,
        dev: HaviDev = HaviDev(),
        contexts: [String: [String: String]] = [:],
        tags: [String: String] = [:],
        strokeColor: String = "#E8542F",
        strokeWidth: Int = 6
    ) {
        self.bundleID = bundleID
        self.screen = screen
        self.viewport = viewport
        self.fragment = fragment
        self.markup = markup
        self.cssPath = cssPath
        self.comment = comment
        self.priority = priority
        self.deviceInfo = deviceInfo
        self.appLogs = appLogs
        self.dev = dev
        self.contexts = contexts
        self.tags = tags
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }
}
