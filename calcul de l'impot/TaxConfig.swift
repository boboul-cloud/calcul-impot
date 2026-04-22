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

struct KmTierConfig: Codable, Equatable {
    let maxKm: Int? // nil = infinity (last tier)
    let coeff: Double
    let constant: Double
}

struct KmBandConfig: Codable, Equatable {
    let minCV: Int
    let maxCV: Int
    let label: String
    let tiers: [KmTierConfig]
}

struct KmVehicleConfig: Codable, Equatable {
    let bands: [KmBandConfig]
}

struct KmAllowanceConfig: Codable, Equatable {
    let scaleYear: Int
    let revenueYear: Int
    let source: String
    let car: KmVehicleConfig
    let moto: KmVehicleConfig
    let scooter: KmVehicleConfig

    static let `default` = KmAllowanceConfig(
        scaleYear: 2026,
        revenueYear: 2025,
        source: "Arrêté officiel (à vérifier chaque année)",
        car: .init(bands: [
            .init(minCV: 1, maxCV: 3, label: "3 CV et moins", tiers: [
                .init(maxKm: 5_000, coeff: 0.529, constant: 0),
                .init(maxKm: 20_000, coeff: 0.316, constant: 1_065),
                .init(maxKm: nil, coeff: 0.370, constant: 0)
            ]),
            .init(minCV: 4, maxCV: 4, label: "4 CV", tiers: [
                .init(maxKm: 5_000, coeff: 0.606, constant: 0),
                .init(maxKm: 20_000, coeff: 0.340, constant: 1_330),
                .init(maxKm: nil, coeff: 0.407, constant: 0)
            ]),
            .init(minCV: 5, maxCV: 5, label: "5 CV", tiers: [
                .init(maxKm: 5_000, coeff: 0.636, constant: 0),
                .init(maxKm: 20_000, coeff: 0.357, constant: 1_395),
                .init(maxKm: nil, coeff: 0.427, constant: 0)
            ]),
            .init(minCV: 6, maxCV: 6, label: "6 CV", tiers: [
                .init(maxKm: 5_000, coeff: 0.665, constant: 0),
                .init(maxKm: 20_000, coeff: 0.374, constant: 1_457),
                .init(maxKm: nil, coeff: 0.447, constant: 0)
            ]),
            .init(minCV: 7, maxCV: 12, label: "7 CV et plus", tiers: [
                .init(maxKm: 5_000, coeff: 0.697, constant: 0),
                .init(maxKm: 20_000, coeff: 0.394, constant: 1_515),
                .init(maxKm: nil, coeff: 0.470, constant: 0)
            ])
        ]),
        moto: .init(bands: [
            .init(minCV: 1, maxCV: 2, label: "1 ou 2 CV", tiers: [
                .init(maxKm: 3_000, coeff: 0.395, constant: 0),
                .init(maxKm: 6_000, coeff: 0.099, constant: 891),
                .init(maxKm: nil, coeff: 0.248, constant: 0)
            ]),
            .init(minCV: 3, maxCV: 5, label: "3 a 5 CV", tiers: [
                .init(maxKm: 3_000, coeff: 0.468, constant: 0),
                .init(maxKm: 6_000, coeff: 0.082, constant: 1_158),
                .init(maxKm: nil, coeff: 0.275, constant: 0)
            ]),
            .init(minCV: 6, maxCV: 12, label: "Plus de 5 CV", tiers: [
                .init(maxKm: 3_000, coeff: 0.606, constant: 0),
                .init(maxKm: 6_000, coeff: 0.079, constant: 1_583),
                .init(maxKm: nil, coeff: 0.343, constant: 0)
            ])
        ]),
        scooter: .init(bands: [
            .init(minCV: 1, maxCV: 1, label: "-", tiers: [
                .init(maxKm: 3_000, coeff: 0.315, constant: 0),
                .init(maxKm: 6_000, coeff: 0.079, constant: 711),
                .init(maxKm: nil, coeff: 0.198, constant: 0)
            ])
        ])
    )
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
    let kmAllowance: KmAllowanceConfig?
    // CSG déductible appliquée aux bulletins mensuels de pension/salaire
    // (par défaut 5,9 % — sources : URSSAF / impots.gouv.fr)
    var csgDeductibleRate: Double = 0.059

    // Custom decoding to keep backward compatibility with payloads
    // that don't carry the new csgDeductibleRate field.
    private enum CodingKeys: String, CodingKey {
        case year, revenueYear, label, legalReference, brackets,
             ceilingPerHalfPart, ceilingParentIsole, decote, deduction,
             credits, kmAllowance, csgDeductibleRate
    }

    init(year: Int, revenueYear: Int, label: String, legalReference: String,
         brackets: [TaxBracketConfig], ceilingPerHalfPart: Double, ceilingParentIsole: Double,
         decote: DecoteConfig, deduction: DeductionConfig, credits: CreditsConfig,
         kmAllowance: KmAllowanceConfig?, csgDeductibleRate: Double = 0.059) {
        self.year = year
        self.revenueYear = revenueYear
        self.label = label
        self.legalReference = legalReference
        self.brackets = brackets
        self.ceilingPerHalfPart = ceilingPerHalfPart
        self.ceilingParentIsole = ceilingParentIsole
        self.decote = decote
        self.deduction = deduction
        self.credits = credits
        self.kmAllowance = kmAllowance
        self.csgDeductibleRate = csgDeductibleRate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = try c.decode(Int.self, forKey: .year)
        revenueYear = try c.decode(Int.self, forKey: .revenueYear)
        label = try c.decode(String.self, forKey: .label)
        legalReference = try c.decode(String.self, forKey: .legalReference)
        brackets = try c.decode([TaxBracketConfig].self, forKey: .brackets)
        ceilingPerHalfPart = try c.decode(Double.self, forKey: .ceilingPerHalfPart)
        ceilingParentIsole = try c.decode(Double.self, forKey: .ceilingParentIsole)
        decote = try c.decode(DecoteConfig.self, forKey: .decote)
        deduction = try c.decode(DeductionConfig.self, forKey: .deduction)
        credits = try c.decode(CreditsConfig.self, forKey: .credits)
        kmAllowance = try c.decodeIfPresent(KmAllowanceConfig.self, forKey: .kmAllowance)
        csgDeductibleRate = try c.decodeIfPresent(Double.self, forKey: .csgDeductibleRate) ?? 0.059
    }

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
        ),
        kmAllowance: .default
    )
}

// MARK: - Config Loader

@MainActor @Observable
final class TaxConfigLoader {
    var config: TaxConfig = .default
    var isRemote = false
    var isLoading = false
    var lastUpdate: Date?
    var remoteSourceLabel: String?
    var refreshResult: RefreshResult?

    enum RefreshResult { case success, noChange, error(String) }

    // Primary + fallback source for remote tax configuration.
    // Keep both URLs in sync if you publish through multiple channels.
    private let remoteURLs: [URL] = [
        URL(string: "https://raw.githubusercontent.com/boboul-cloud/tax-config/main/tax_config.json")!,
        URL(string: "https://cdn.jsdelivr.net/gh/boboul-cloud/tax-config@main/tax_config.json")!
    ]

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
        isLoading = true
        defer { isLoading = false }

        for (index, url) in remoteURLs.enumerated() {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                let remote = try JSONDecoder().decode(TaxConfig.self, from: data)
                config = remote
                isRemote = true
                lastUpdate = Date()
                remoteSourceLabel = index == 0 ? "Source principale" : "Source de secours"
                saveToCache(data)
                return
            } catch {
                continue
            }
        }

        // Keep current config (cached or default) if all remote sources fail.
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
