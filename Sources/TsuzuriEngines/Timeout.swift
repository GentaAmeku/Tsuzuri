/// 決めた秒数で打ち切る。先に終わった方の結果を返し、残りは取り消す
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw SonioxError.timedOut(seconds: seconds)
        }
        guard let result = try await group.next() else {
            throw SonioxError.timedOut(seconds: seconds)
        }
        group.cancelAll()
        return result
    }
}
