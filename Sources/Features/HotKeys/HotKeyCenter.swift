import Foundation
import AppKit
import HotKey

@MainActor
public final class HotKeyCenter {
    public typealias Action = @MainActor () -> Void

    private var hotKeys: [String: HotKey] = [:]

    public init() {}

    public func register(id: String, key: Key, modifiers: NSEvent.ModifierFlags, action: @escaping Action) {
        let hk = HotKey(key: key, modifiers: modifiers)
        hk.keyDownHandler = action
        hotKeys[id] = hk
    }

    public func unregister(id: String) {
        hotKeys.removeValue(forKey: id)
    }

    public func unregisterAll() {
        hotKeys.removeAll()
    }

    public var registeredCount: Int { hotKeys.count }
}
