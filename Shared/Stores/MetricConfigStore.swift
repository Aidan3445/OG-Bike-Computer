//
//  MetricConfigStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation
import Combine
import SwiftUI

class MetricConfigStore: ObservableObject {
    @Published var config: MetricPagesConfig {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("metricConfig.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(MetricPagesConfig.self, from: data) {
            config = loaded
        } else {
            config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func applyFromRemote(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(MetricPagesConfig.self, from: data) else { return }
        DispatchQueue.main.async {
            self.config = decoded
        }
    }

    var encodedConfig: Data? {
        try? JSONEncoder().encode(config)
    }

    func addPage(_ page: MetricPage) {
        config.pages.append(page)
    }

    func removePage(at index: Int) {
        guard config.pages.indices.contains(index) else { return }
        config.pages.remove(at: index)
    }

    func movePage(from source: IndexSet, to destination: Int) {
        config.pages.move(fromOffsets: source, toOffset: destination)
    }

    func resetToDefault() {
        config = .default
    }
}
