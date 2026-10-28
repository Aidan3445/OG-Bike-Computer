//
//  DiagnosticsLog.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 10/27/26.
//

#if !WIDGET_EXTENSION
import Foundation
import os

/// Debug-only trace files in Documents/Diagnostics. Every file operation runs
/// on `queue`, so a snapshot taken there never catches half a row.
nonisolated enum DiagnosticsLog {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static let subsystem = "com.aidan3445.OG-Bike-Computer"
    static let queue = DispatchQueue(label: "com.aidan3445.OG-Bike-Computer.diagnostics", qos: .utility)

    static let eventsFileName = "events.log"
    static let rotatedEventsFileName = "events.1.log"
    private static let maxEventsBytes: UInt64 = 1_000_000

    /// CSVs that are still being written. Only touched on `queue`.
    fileprivate static var openCSVPaths: Set<String> = []

    private static let timeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var directory: URL {
        documentsSubdirectory("Diagnostics")
    }

    /// Snapshots waiting to go to the phone. Kept in Documents because
    /// WatchConnectivity retries queued transfers after a relaunch.
    static var outboxDirectory: URL {
        documentsSubdirectory("DiagnosticsOutbox")
    }

    /// Files the watch sent. Event logs sit at the top, CSVs in one folder per ride.
    static var watchDirectory: URL {
        let dir = directory.appendingPathComponent("watch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func documentsSubdirectory(_ name: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Events

    static func event(_ category: String, _ message: String) {
        Logger(subsystem: subsystem, category: category).log("\(message, privacy: .public)")
        #if DEBUG
        let date = Date()
        let flat = message.replacingOccurrences(of: "\n", with: " ")
        queue.async {
            appendEvent("\(timeFormatter.string(from: date)),\(category),\(flat)\n")
        }
        #endif
    }

    private static func appendEvent(_ line: String) {
        let fm = FileManager.default
        let url = directory.appendingPathComponent(eventsFileName)
        if UInt64(fileSize(url)) >= maxEventsBytes {
            let rotated = directory.appendingPathComponent(rotatedEventsFileName)
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
    }

    // MARK: - Files

    /// This ride's CSVs in `directory`.
    static func rideFiles(rideID: UUID) -> [URL] {
        let prefix = rideID.uuidString + "."
        return topLevelFiles().filter {
            $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "csv"
        }
    }

    /// Every CSV plus both event logs.
    static func allSendableFiles() -> [URL] {
        topLevelFiles().filter {
            $0.pathExtension == "csv"
                || $0.lastPathComponent == eventsFileName
                || $0.lastPathComponent == rotatedEventsFileName
        }
    }

    static func topLevelFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// Copies `url` into the outbox and calls back on `queue` with the copy
    /// and the source size at the moment it was taken.
    static func snapshot(_ url: URL, completion: @escaping (URL?, Int64) -> Void) {
        queue.async {
            let size = fileSize(url)
            let dest = outboxDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                completion(dest, size)
            } catch {
                completion(nil, size)
            }
        }
    }

    /// Drops snapshots whose transfer never reported back.
    static func pruneOutbox(olderThan age: TimeInterval) {
        queue.async {
            let cutoff = Date().addingTimeInterval(-age)
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: outboxDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in urls {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// Deletes a sent CSV unless it's still open or grew since its snapshot.
    /// Event logs only ever rotate.
    static func removeSentSource(fileName: String, snapshotSize: Int64) {
        queue.async {
            guard fileName.hasSuffix(".csv") else { return }
            let url = directory.appendingPathComponent((fileName as NSString).lastPathComponent)
            guard !openCSVPaths.contains(url.path), fileSize(url) == snapshotSize else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Copies a file from the watch into `watchDirectory`, overwriting. Runs
    /// synchronously because the system deletes the file when the delegate returns.
    @discardableResult
    static func storeWatchFile(_ source: URL, rideID: UUID?, fileName: String) -> URL? {
        queue.sync {
            let name = (fileName as NSString).lastPathComponent
            var dir = watchDirectory
            if let rideID, !isEventLog(name) {
                dir = dir.appendingPathComponent(rideID.uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let dest = dir.appendingPathComponent(name)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: source, to: dest)
                return dest
            } catch {
                return nil
            }
        }
    }

    static func isEventLog(_ fileName: String) -> Bool {
        fileName == eventsFileName || fileName == rotatedEventsFileName
    }

    /// Keeps the newest `keep` ride folders the watch sent.
    static func pruneWatchRideFolders(keep: Int) {
        queue.async {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: watchDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey])) ?? []
            let folders = urls
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
                .map { url in
                    (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast)
                }
                .sorted { $0.1 > $1.1 }
            for (url, _) in folders.dropFirst(keep) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func deleteAll(completion: @escaping () -> Void) {
        queue.async {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }
}

extension Notification.Name {
    /// Posted on the main thread when a diagnostics file arrives from the watch.
    static let diagnosticsFilesChanged = Notification.Name("diagnosticsFilesChanged")
}

/// A per-ride CSV at Documents/Diagnostics/<rideID>.<kind>.csv. Rows are
/// buffered and written on `DiagnosticsLog.queue` every 10 s or on `flush()`.
/// Its mutable state is only touched on that queue.
nonisolated final class DiagnosticsCSV: @unchecked Sendable {
    let url: URL
    private let headerLine: String
    private var buffer: [String] = []
    private var timer: DispatchSourceTimer?

    init?(rideID: UUID, kind: String, header: [String]) {
        guard DiagnosticsLog.isEnabled else { return nil }
        url = DiagnosticsLog.directory.appendingPathComponent("\(rideID.uuidString).\(kind).csv")
        headerLine = header.joined(separator: ",") + "\n"

        let timer = DispatchSource.makeTimerSource(queue: DiagnosticsLog.queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.writeBuffer() }
        self.timer = timer

        DiagnosticsLog.queue.async { [self] in
            DiagnosticsLog.openCSVPaths.insert(url.path)
            writeBuffer()
        }
        timer.resume()
    }

    deinit {
        timer?.cancel()
        let path = url.path
        DiagnosticsLog.queue.async { DiagnosticsLog.openCSVPaths.remove(path) }
    }

    func append(_ fields: [Any?]) {
        let line = fields.map(Self.format).joined(separator: ",") + "\n"
        DiagnosticsLog.queue.async { [self] in buffer.append(line) }
    }

    func flush() {
        DiagnosticsLog.queue.async { [self] in writeBuffer() }
    }

    func close() {
        DiagnosticsLog.queue.async { [self] in
            writeBuffer()
            timer?.cancel()
            timer = nil
            DiagnosticsLog.openCSVPaths.remove(url.path)
        }
    }

    /// Writes the header too when the file is missing, which covers a new
    /// ride and a file deleted after it was sent.
    private func writeBuffer() {
        let fm = FileManager.default
        var text = buffer.joined()
        buffer.removeAll(keepingCapacity: true)
        if !fm.fileExists(atPath: url.path) {
            text = headerLine + text
            fm.createFile(atPath: url.path, contents: nil)
        }
        guard !text.isEmpty, let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        try? handle.close()
    }

    private static func format(_ field: Any?) -> String {
        guard let field = unwrap(field) else { return "" }
        switch field {
        case let date as Date:
            return String(format: "%.3f", date.timeIntervalSince1970)
        case let bool as Bool:
            return bool ? "1" : "0"
        case let double as Double:
            return double.isFinite ? String(double) : ""
        case let string as String:
            guard string.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return string }
            return "\"" + string.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        default:
            return "\(field)"
        }
    }

    /// Optionals passed through `Any?` arrive double-wrapped.
    private static func unwrap(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.map { unwrap($0.value) } ?? nil
    }
}
#endif
