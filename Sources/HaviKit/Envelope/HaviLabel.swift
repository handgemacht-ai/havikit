import Foundation

/// One applied workspace label, emitted into the envelope as a `TextualBody`
/// with `purpose: "tagging"` and an `x:labelKey` naming the label
/// (`.claude/rules/w3c-annotations.md`). `value` carries the applied value for a
/// `choice`/`value` label; a `flag` label applies with `value == nil`, so the
/// builder omits the `value` field entirely — matching the browser extension's
/// shape (`assets/shared/annotation-envelope.js`, where a flag emits no value).
///
/// `priority` is just a label with `key == "priority"`; the built-in priority
/// control feeds it through `HaviEnvelopeInput.priority` instead, so the builder
/// skips any `"priority"` entry that also appears here to avoid a duplicate body.
public struct HaviLabel: Sendable, Equatable {
    public var key: String
    public var value: String?

    public init(key: String, value: String? = nil) {
        self.key = key
        self.value = value
    }
}
