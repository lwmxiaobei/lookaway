import Foundation

/// MACDUO_TRACE=1 时把每一帧姿态写成 CSV，用来诊断零点和判定边界。
/// 默认完全不启用，也不占任何开销。
final class TraceLogger {
    private let handle: FileHandle?
    private var lastWrite: TimeInterval = 0
    /// 限流：姿态更新有 25~50Hz，全写下来没必要
    private let minimumInterval: TimeInterval = 0.1

    let path: String

    init?() {
        guard ProcessInfo.processInfo.environment["MACDUO_TRACE"] == "1" else { return nil }

        path = ProcessInfo.processInfo.environment["MACDUO_TRACE_PATH"] ?? "/tmp/macduo-trace.csv"
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        write(line: "time,rawYaw,baseline,deviation,leftBound,rightBound,state")
    }

    /// 状态翻转必须记下来，不受限流影响
    func record(
        rawYaw: Double?,
        baseline: Double?,
        deviation: Double,
        leftBound: Double,
        rightBound: Double,
        state: String,
        force: Bool = false
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        guard force || now - lastWrite >= minimumInterval else { return }
        lastWrite = now

        write(line: String(
            format: "%.3f,%@,%@,%.1f,%.1f,%.1f,%@",
            now,
            rawYaw.map { String(format: "%.1f", $0) } ?? "",
            baseline.map { String(format: "%.1f", $0) } ?? "",
            deviation, leftBound, rightBound, state
        ))
    }

    func note(_ text: String) {
        write(line: "# \(text)")
    }

    private func write(line: String) {
        guard let handle, let data = (line + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }
}
