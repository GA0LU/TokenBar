// workbuddy-diag.swift — WorkBuddy status-channel diagnostic (v1.1.2 logic).
// Replicates TokenBar's global-scan judgment so you can check from a shell
// what the Touch Bar card should currently read, and why.
//
// Usage:  swift scripts/workbuddy-diag.swift
//
// Output: candidate session logs (mtime window), each one's freshest
// ModelProvider stream marker within 90s, and the global decision.

import Foundation

let WINDOW: TimeInterval = 90
let STALE: TimeInterval = 120

func candidateLogs() -> [(path: String, mtime: Date)] {
    let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".workbuddy/logs")
    guard let dayDirs = try? FileManager.default.contentsOfDirectory(
        at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return [] }
    let cutoff = Date().addingTimeInterval(-STALE)
    var out: [(path: String, mtime: Date)] = []
    for day in dayDirs where day.hasDirectoryPath {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: day, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { continue }
        for f in files where f.pathExtension == "log" {
            let name = f.lastPathComponent
            guard name.contains("__"),
                  !name.hasPrefix("__"),
                  !name.hasPrefix("unknown-workspace"),
                  !name.hasPrefix("workbuddyMainThread"),
                  !name.hasPrefix("daemon-"),
                  !name.hasPrefix("edge-sync"),
                  !name.hasPrefix("extension-scheduler-") else { continue }
            let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            guard mtime > cutoff else { continue }
            out.append((f.path, mtime))
        }
    }
    return out.sorted { $0.mtime > $1.mtime }
}

func lastActivity(in logPath: String, window: TimeInterval) -> Date? {
    guard let handle = FileHandle(forReadingAtPath: logPath) else { return nil }
    defer { try? handle.close() }
    let size = (try? handle.seekToEnd()) ?? 0
    guard size > 0 else { return nil }
    let tailBytes = min(size, 12_000_000)
    try? handle.seek(toOffset: size - tailBytes)
    guard let data = try? handle.read(upToCount: Int(tailBytes)),
          let text = String(data: data, encoding: .utf8) else { return nil }
    let markers = ["Stream progress", "First raw chunk received",
                   "First meaningful token received", "Stream idle monitor armed"]
    let tsRegex = try? NSRegularExpression(
        pattern: #"\[(\d{1,2}/\d{1,2}/\d{4}), (\d{1,2}:\d{2}:\d{2} [AP]M)"#
    )
    let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "M/d/yyyy, h:mm:ss a"; fmt.timeZone = .current
    let now = Date(); var latest: Date?
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let s = String(line)
        guard markers.contains(where: { s.contains($0) }) else { continue }
        guard let tsRegex, let match = tsRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: s),
              let d = fmt.date(from: String(s[r])), now.timeIntervalSince(d) <= window else { continue }
        if latest == nil || d > latest! { latest = d }
    }
    return latest
}

let now = Date()
let candidates = candidateLogs()
print("\(URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent)  \(now)  candidates(stale<\(Int(STALE))s): \(candidates.count)")
var best: (Date, String)?
let sizeFmt = ByteCountFormatter()
sizeFmt.countStyle = .file
for (path, mtime) in candidates {
    let name = URL(fileURLWithPath: path).lastPathComponent
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    let age = now.timeIntervalSince(mtime)
    let act = lastActivity(in: path, window: WINDOW)
    let actStr = act.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "None"
    print("  \(name.prefix(46))  \(sizeFmt.string(fromByteCount: Int64(size)))  mtime_age=\(String(format: "%6.1f", age))s  stream_in_90s=\(actStr)")
    if let act, best == nil || act > best!.0 { best = (act, path) }
}
if let best {
    let project = URL(fileURLWithPath: best.1).lastPathComponent.split(separator: "__").first.map(String.init) ?? "?"
    print("DECISION: WORKING · \(project) @ \(DateFormatter.localizedString(from: best.0, dateStyle: .none, timeStyle: .medium))")
} else {
    print("DECISION: IDLE (no ModelProvider stream in \(Int(WINDOW))s across all live logs)")
}
