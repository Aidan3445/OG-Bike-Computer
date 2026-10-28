//
//  DiagnosticsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 10/27/26.
//

#if DEBUG
import SwiftUI

/// Trace files from this phone and the watch, grouped by ride.
struct DiagnosticsView: View {
    @ObservedObject var rideStore: RideStore
    @StateObject private var connectivity = ConnectivityManager.shared
    @State private var eventLogs: [DiagnosticsFile] = []
    @State private var rideGroups: [RideGroup] = []
    @State private var shareItems: ShareItems?
    @State private var isRequesting = false
    @State private var requestStatus: String?
    @State private var isPreparingShare = false
    @State private var showDeleteConfirm = false

    struct DiagnosticsFile: Identifiable {
        let url: URL
        let label: String
        let isWatch: Bool
        let size: Int64
        var id: String { url.path }

        /// Prefixed with the device so phone and watch logs don't collide in a share.
        var shareName: String {
            (isWatch ? "watch-" : "phone-") + url.lastPathComponent
        }
    }

    struct RideGroup: Identifiable {
        let rideID: String
        let files: [DiagnosticsFile]
        let modified: Date
        var id: String { rideID }
    }

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    var body: some View {
        List {
            Section {
                Button {
                    requestWatchFiles()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Request Watch Files")
                                if isRequesting {
                                    ProgressView().controlSize(.mini)
                                }
                            }
                            Text(requestStatus ?? (connectivity.isReachable ? "Watch reachable" : "Watch not reachable"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "applewatch.radiowaves.left.and.right")
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(!connectivity.isReachable || isRequesting)

                Button {
                    shareAll()
                } label: {
                    Label {
                        HStack(spacing: 6) {
                            Text("Share All")
                            if isPreparingShare {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.up.on.square")
                            .foregroundStyle(.green)
                    }
                }
                .disabled(isEmpty || isPreparingShare)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label {
                        Text("Delete All")
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isEmpty)
            }

            Section("Event Logs") {
                if eventLogs.isEmpty {
                    Text("No event logs yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(eventLogs) { file in
                    fileRow(file)
                }
            }

            ForEach(rideGroups) { group in
                Section {
                    ForEach(group.files) { file in
                        fileRow(file)
                    }
                } header: {
                    rideHeader(group.rideID)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear(perform: reload)
        .refreshable { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .diagnosticsFilesChanged)) { _ in
            reload()
        }
        .confirmationDialog("Delete all diagnostics files on this phone?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                DiagnosticsLog.deleteAll(completion: reload)
            }
        }
        .sheet(item: $shareItems) { items in
            ShareSheet(activityItems: items.urls)
        }
    }

    private var isEmpty: Bool {
        eventLogs.isEmpty && rideGroups.isEmpty
    }

    private func fileRow(_ file: DiagnosticsFile) -> some View {
        Button {
            share(file)
        } label: {
            HStack {
                Label(file.label, systemImage: file.isWatch ? "applewatch" : "iphone")
                Spacer()
                Text(formattedStorageSize(file.size))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func rideHeader(_ rideID: String) -> some View {
        if let ride = rideStore.rides.first(where: { $0.id.uuidString == rideID }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ride.name)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ride.date.formatted(date: .abbreviated, time: .shortened))
            }
        } else {
            Text(rideID)
        }
    }

    // MARK: - Files

    private func reload() {
        DiagnosticsLog.queue.async {
            let (logs, groups) = Self.scan()
            DispatchQueue.main.async {
                eventLogs = logs
                rideGroups = groups
            }
        }
    }

    /// Phone CSVs sit at the top of the Diagnostics folder, watch CSVs in
    /// watch/<rideID>/. Both are grouped by the ride ID their name starts with.
    nonisolated private static func scan() -> ([DiagnosticsFile], [RideGroup]) {
        let fm = FileManager.default
        let phoneDir = DiagnosticsLog.directory
        let watchDir = DiagnosticsLog.watchDirectory
        let logNames = [DiagnosticsLog.eventsFileName, DiagnosticsLog.rotatedEventsFileName]

        var logs: [DiagnosticsFile] = []
        for (dir, isWatch) in [(phoneDir, false), (watchDir, true)] {
            for name in logNames {
                let url = dir.appendingPathComponent(name)
                guard fm.fileExists(atPath: url.path) else { continue }
                logs.append(DiagnosticsFile(
                    url: url,
                    label: "\(isWatch ? "Watch" : "Phone") \(name)",
                    isWatch: isWatch,
                    size: DiagnosticsLog.fileSize(url)))
            }
        }

        var filesByRide: [String: [DiagnosticsFile]] = [:]
        var modifiedByRide: [String: Date] = [:]

        func add(_ url: URL, rideID: String, isWatch: Bool) {
            let prefix = rideID + "."
            let name = url.lastPathComponent
            let label = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
            filesByRide[rideID, default: []].append(DiagnosticsFile(
                url: url, label: label, isWatch: isWatch, size: DiagnosticsLog.fileSize(url)))
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            modifiedByRide[rideID] = max(modifiedByRide[rideID] ?? .distantPast, modified)
        }

        for url in DiagnosticsLog.topLevelFiles() where url.pathExtension == "csv" {
            let rideID = String(url.lastPathComponent.prefix { $0 != "." })
            add(url, rideID: rideID, isWatch: false)
        }

        let folders = (try? fm.contentsOfDirectory(
            at: watchDir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders
        where (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files {
                add(url, rideID: folder.lastPathComponent, isWatch: true)
            }
        }

        let groups = filesByRide.map { rideID, files in
            RideGroup(
                rideID: rideID,
                files: files.sorted { ($0.isWatch ? 1 : 0, $0.label) < ($1.isWatch ? 1 : 0, $1.label) },
                modified: modifiedByRide[rideID] ?? .distantPast)
        }
        .sorted { $0.modified > $1.modified }

        return (logs, groups)
    }

    /// Shares a copy so the live file can keep growing.
    private func share(_ file: DiagnosticsFile) {
        DiagnosticsLog.queue.async {
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(file.shareName)
            try? FileManager.default.removeItem(at: dest)
            guard (try? FileManager.default.copyItem(at: file.url, to: dest)) != nil else { return }
            DispatchQueue.main.async {
                shareItems = ShareItems(urls: [dest])
            }
        }
    }

    private func shareAll() {
        isPreparingShare = true
        DiagnosticsLog.queue.async {
            let url = Self.zipDiagnostics()
            DispatchQueue.main.async {
                isPreparingShare = false
                if let url {
                    shareItems = ShareItems(urls: [url])
                }
            }
        }
    }

    /// Zips the whole Diagnostics folder. The coordinator's zip only lives
    /// inside its closure, so it's copied out.
    nonisolated private static func zipDiagnostics() -> URL? {
        let fm = FileManager.default
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let dest = fm.temporaryDirectory.appendingPathComponent("Diagnostics-\(stamp).zip")
        try? fm.removeItem(at: dest)

        var copied = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: DiagnosticsLog.directory, options: [.forUploading], error: &coordError
        ) { zipURL in
            copied = (try? fm.copyItem(at: zipURL, to: dest)) != nil
        }
        return copied && coordError == nil ? dest : nil
    }

    private func requestWatchFiles() {
        isRequesting = true
        requestStatus = nil
        connectivity.requestWatchDiagnostics { result in
            isRequesting = false
            switch result {
            case .success(let count):
                requestStatus = count == 1 ? "Watch is sending 1 file" : "Watch is sending \(count) files"
            case .failure(let error):
                requestStatus = "Request failed: \(error.localizedDescription)"
            }
        }
    }
}
#endif
