import Combine
import Foundation

/// Display order only: rearranging a card never saves, captures, renumbers, or syncs a post.
/// IDs include their source because shared-form entries and legacy posts have separate stores.
@MainActor
final class PostCardOrderStore: ObservableObject {
    static let defaultsKey = "savy.socialPosts.cardOrder.v1"

    @Published private(set) var manualOrder: [String]?
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? SavyCardPreferences.defaults
        self.defaults = defaults
        manualOrder = defaults.stringArray(forKey: Self.defaultsKey).map(Self.unique)
    }

    /// Before the first move, the existing status/date order remains authoritative.
    /// Afterwards, newly observed IDs append in that same predictable default order.
    func orderedIDs(defaultOrder: [String], pinnedIDs: Set<String>) -> [String] {
        let available = Self.unique(defaultOrder)
        let order: [String]
        if let manualOrder {
            let availableIDs = Set(available)
            let retained = manualOrder.filter { availableIDs.contains($0) }
            let retainedIDs = Set(retained)
            order = retained + available.filter { !retainedIDs.contains($0) }
        } else {
            order = available
        }
        return order.filter { pinnedIDs.contains($0) } + order.filter { !pinnedIDs.contains($0) }
    }

    /// Called when the visible inventory changes, outside SwiftUI's body evaluation.
    /// Absent IDs remain reserved: a source can be temporarily empty while it refreshes.
    /// They never appear in the displayed order, and returning records keep their place.
    func reconcile(defaultOrder: [String]) {
        guard let manualOrder else { return }
        let available = Self.unique(defaultOrder)
        let knownIDs = Set(manualOrder)
        save(manualOrder + available.filter { !knownIDs.contains($0) })
    }

    /// Move exactly one slot within the current pinned or unpinned block.
    @discardableResult
    func move(_ id: String, direction: Int, defaultOrder: [String], pinnedIDs: Set<String>) -> Bool {
        guard direction == -1 || direction == 1 else { return false }
        var order = orderedIDs(defaultOrder: defaultOrder, pinnedIDs: pinnedIDs)
        guard let index = order.firstIndex(of: id) else { return false }
        let destination = index + direction
        guard order.indices.contains(destination),
              pinnedIDs.contains(order[destination]) == pinnedIDs.contains(id) else { return false }
        order.swapAt(index, destination)
        if let manualOrder {
            // Move visible cards through their existing slots, leaving absent IDs reserved.
            let availableIDs = Set(order)
            var reordered = order.makeIterator()
            let retained = manualOrder.map { availableIDs.contains($0) ? reordered.next()! : $0 }
            save(retained + Array(reordered))
        } else {
            save(order)
        }
        return true
    }

    private func save(_ order: [String]) {
        guard manualOrder != order else { return }
        manualOrder = order
        defaults.set(order, forKey: Self.defaultsKey)
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
