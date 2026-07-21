import os

/// Heap-allocated `os_unfair_lock` wrapper. Guards the log ring and context
/// store so `Havi.log` / `Havi.setContext` stay `nonisolated` and cheap from any
/// thread (design §1 threading). Allocating the lock on the heap keeps the
/// pointer stable, which taking `&` of a stored `os_unfair_lock` property does
/// not guarantee.
final class HaviUnfairLock: @unchecked Sendable {
    private let unfairLock: os_unfair_lock_t

    init() {
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(unfairLock)
        defer { os_unfair_lock_unlock(unfairLock) }
        return try body()
    }
}
