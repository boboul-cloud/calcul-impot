//
//  TaxConfig.swift
//  calcul de l'impot
//
//  Created by Robert Oulhen on 12/04/2026.
//

import Foundation
import Observation

// MARK: - Tax Configuration Model

struct TaxBracketConfig: Codable, Equatable {
    let upperBound: Double?  // nil = infinity (last bracket)
    let rate: Double
}

struct DecoteConfig: Codable, Equatable {
    let singleThreshold: Double
    let coupleThreshold: Double
    let singleForfait: Double
    let coupleForfait: Double
    let coefficient: Double
}

struct DeductionConfig: Codable, Equatable {
    let rate: Double
    let min: Double
    let max: Double
}

struct EmploiDomicileConfig: Codable, Equatable {
    let rate: Double
    let baseCap: Double
    let perChildBonus: Double
    let maxCap: Double
}

struct DonsAideConfig: Codable, Equatable {
    let rate: Double
    let cap: Double
}

struct DonsAutresConfig: Codable, Equatable {
    let rate: Double
    let incomePercentCap: Double
}

struct CreditsConfig: Codable, Equatable {
    let emploiDomicile: EmploiDomicileConfig
    let donsAide: DonsAideConfig
    let donsAutres: DonsAutresConfig
}

struct TaxConfig: Codable, Equatable {
    let year: Int
    let revenueYear: Int
    let label: String
    let legalReference: String
    let brackets: [TaxBracketConfig]
    let ceilingPerHalfPart: Double
    let ceilingParentIsole: Double
    let decote: DecoteConfig
    let deduction: DeductionConfig
    let credits: CreditsConfig

    static let `default` = TaxConfig(
        year: 2026,
        revenueYear: 2025,
        label: "Barème 2026 — Revenus 2025",
        legalReference: "Loi de finances du 19/02/2026",
        brackets: [
            .init(upperBound: 11_600, rate: 0.00),
            .init(upperBound: 29_579, rate: 0.11),
            .init(upperBound: 84_577, rate: 0.30),
            .init(upperBound: 181_917, rate: 0.41),
            .init(upperBound: nil, rate: 0.45)
        ],
        ceilingPerHalfPart: 1_807,
        ceilingParentIsole: 4_262,
        decote: .init(
            singleThreshold: 1_982,
            coupleThreshold: 3_277,
            singleForfait: 897,
            coupleForfait: 1_483,
            coefficient: 0.4525
        ),
        deduction: .init(rate: 0.10, min: 504, max: 14_426),
        credits: .init(
            emploiDomicile: .init(rate: 0.50, baseCap: 12_000, perChildBonus: 1_500, maxCap: 15_000),
            donsAide: .init(rate: 0.75, cap: 1_000),
            donsAutres: .init(rate: 0.66, incomePercentCap: 0.20)
        )
    )
}

// MARK: - Config Loader

@MainActor @Observable
final class TaxConfigLoader {
    var config: TaxConfig = .default
    var isRemote = false
    var isLoading = false
    var lastUpdate: Date?
    var refreshResult: RefreshResult?

    enum RefreshResult { case success, noChange, error(String) }

    // Change this URL to your hosted JSON config
    // e.g. https://raw.githubusercontent.com/<user>/<repo>/main/tax_config.json
    private let remoteURL = URL(string: "https://raw.githubusercontent.com/boboul-cloud/tax-config/main/tax_config.json")

    private let cacheKey = "cached_tax_config"
    private let cacheDateKey = "cached_tax_config_date"
    private let cacheTTL: TimeInterval = 86_400 // 24h

    func load() async {
        // Try cache first
        if let cached = loadFromCache() {
            config = cached
            isRemote = true
            lastUpdate = UserDefaults.standard.object(forKey: cacheDateKey) as? Date
        }

        // Fetch remote if cache is stale or missing
        await fetchRemote()
    }

    func forceRefresh() async {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheDateKey)
        let oldConfig = config
        await fetchRemote()
        if !isRemote {
            refreshResult = .error("Impossible de contacter le serveur")
        } else if config == oldConfig {
            refreshResult = .noChange
        } else {
            refreshResult = .success
        }
    }

    private func fetchRemote() async {
        guard let url = remoteURL else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let remote = try JSONDecoder().decode(TaxConfig.self, from: data)
            config = remote
            isRemote = true
            lastUpdate = Date()
            saveToCache(data)
        } catch {
            // Keep current config (cached or default)
        }
    }

    private func loadFromCache() -> TaxConfig? {
        guard let date = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
              Date().timeIntervalSince(date) < cacheTTL,
              let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(TaxConfig.self, from: data)
    }

    private func saveToCache(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
    }
}
