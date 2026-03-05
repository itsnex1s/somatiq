import Foundation

@MainActor
protocol DashboardSnapshotProviding: AnyObject {
    func fetchSnapshot(forceRecalculate: Bool) async throws -> DashboardSnapshot
    func fetchCachedSnapshot() throws -> DashboardSnapshot?
}
