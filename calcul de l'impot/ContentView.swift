//
//  ContentView.swift
//  calcul de l'impot
//
//  Created by Robert Oulhen on 12/04/2026.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

// MARK: - Model

enum FamilySituation: String, CaseIterable, Identifiable {
    case single = "Célibataire"
    case couple = "Couple"
    case singleParent = "Parent isolé"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .single: "person.fill"
        case .couple: "person.2.fill"
        case .singleParent: "figure.and.child.holdinghands"
        }
    }
}

struct TaxBracketDetail {
    let range: String
    let rate: Double
    let amount: Double
}

struct TaxResult {
    let parts: Double
    let quotientFamilial: Double
    let taxBrut: Double
    let plafonnement: Double
    let decote: Double
    let taxNet: Double
    let creditEmploiDomicile: Double
    let creditDonsAide: Double
    let creditDonsAutres: Double
    let taxAfterCredits: Double
    let marginalRate: Double
    let averageRate: Double
    let brackets: [TaxBracketDetail]
}

enum AdditionalEntryKind: String, CaseIterable, Identifiable {
    case taxableIncome = "Revenu imposable"
    case deductibleCharge = "Charge déductible"
    case taxCredit = "Crédit / réduction"
    case withholdingPaid = "Prélèvement déjà payé"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .taxableIncome: "plus.circle.fill"
        case .deductibleCharge: "minus.circle.fill"
        case .taxCredit: "gift.fill"
        case .withholdingPaid: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .taxableIncome: .orange
        case .deductibleCharge: .blue
        case .taxCredit: .green
        case .withholdingPaid: .mint
        }
    }
}

struct AdditionalTaxEntry: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var suggestedBox: String
    var kind: AdditionalEntryKind
    var amountText: String = ""
    var note: String = ""
}

struct TaxChatMessage: Identifiable, Hashable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
}

struct FrequentTaxTemplate: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let box: String
    let kind: AdditionalEntryKind
    let note: String
}

enum CreditHelpTopic: String, Identifiable {
    case emploiDomicile
    case donsAide
    case donsAutres

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emploiDomicile: return "Emploi à domicile"
        case .donsAide: return "Dons - aide aux personnes"
        case .donsAutres: return "Dons - autres organismes"
        }
    }

    var declarationBox: String {
        switch self {
        case .emploiDomicile: return "7DB"
        case .donsAide: return "7UD"
        case .donsAutres: return "7UF"
        }
    }

    var taxNature: String {
        switch self {
        case .emploiDomicile: return "Crédit d'impôt"
        case .donsAide, .donsAutres: return "Réduction d'impôt"
        }
    }
}

struct GeneratedTaxPDF {
    let url: URL
    let data: Data
}

struct TaxPDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let data: Data
    let isA4Optimized: Bool
}

enum AITaxFormAssistant {
    static func suggestEntries(query: String, apiKey: String) async -> (message: String, entries: [AdditionalTaxEntry]) {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localFallback(query: query)
        }

        let prompt = """
        Tu es un assistant fiscal FR.
        À partir de la demande utilisateur, propose les cases fiscales pertinentes à remplir.

        Réponds UNIQUEMENT en JSON strict de ce format:
        {
          "message": "explication courte",
          "entries": [
            {
              "title": "nom clair",
              "kind": "taxable_income|deductible_charge|tax_credit|withholding_paid",
              "suggested_box": "ex: 7DB",
              "why": "pourquoi cette case"
            }
          ]
        }

        Contraintes:
        - Propose entre 1 et 5 entrées maximum.
        - Si la demande est vague, propose les plus probables et indique une prudence dans message.
        - N'invente pas de montants.

        Demande utilisateur:
        \(query)
        """

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return localFallback(query: query)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return localFallback(query: query)
        }

        let cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return localFallback(query: query)
        }

        let messageText = (root["message"] as? String) ?? "Voici des cases qui semblent pertinentes."
        let rawEntries = root["entries"] as? [[String: Any]] ?? []

        let entries = rawEntries.prefix(5).compactMap { item -> AdditionalTaxEntry? in
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let box = (item["suggested_box"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let why = (item["why"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let kindRaw = (item["kind"] as? String ?? "").lowercased()

            let kind: AdditionalEntryKind
            switch kindRaw {
            case "taxable_income": kind = .taxableIncome
            case "deductible_charge": kind = .deductibleCharge
            case "tax_credit": kind = .taxCredit
            case "withholding_paid": kind = .withholdingPaid
            default: kind = .deductibleCharge
            }

            guard !title.isEmpty else { return nil }
            return AdditionalTaxEntry(
                title: title,
                suggestedBox: box,
                kind: kind,
                amountText: "",
                note: why
            )
        }

        if entries.isEmpty {
            return localFallback(query: query)
        }
        return (messageText, entries)
    }

    private static func localFallback(query: String) -> (message: String, entries: [AdditionalTaxEntry]) {
        let q = query.lowercased()
        var entries: [AdditionalTaxEntry] = []

        func add(_ title: String, _ box: String, _ kind: AdditionalEntryKind, _ note: String) {
            entries.append(.init(title: title, suggestedBox: box, kind: kind, note: note))
        }

        if q.contains("garde") || q.contains("enfant") {
            add("Frais de garde d'enfants", "7GA-7GG", .taxCredit, "Crédit d'impôt lié aux frais de garde")
        }
        if q.contains("pension") {
            add("Pension alimentaire versée", "6GU", .deductibleCharge, "Charge potentiellement déductible du revenu")
        }
        if q.contains("foncier") || q.contains("loyer") {
            add("Revenus fonciers", "4BA", .taxableIncome, "Revenus locatifs à intégrer")
        }
        if q.contains("travaux") || q.contains("renov") {
            add("Travaux / charges déductibles", "4BC", .deductibleCharge, "Selon le régime fiscal applicable")
        }
        if q.contains("emploi") || q.contains("domicile") {
            add("Emploi à domicile", "7DB", .taxCredit, "Crédit d'impôt services à la personne")
        }

        if entries.isEmpty {
            add("Autre charge déductible", "À confirmer", .deductibleCharge, "Précisez votre situation pour cibler la bonne case")
            return ("Je n'ai pas de clé IA active, j'ai ajouté une proposition générique. Donnez plus de détails pour affiner.", entries)
        }

        return ("J'ai ajouté des cases probables selon votre demande. Vérifiez la correspondance avec votre déclaration.", entries)
    }
}

// MARK: - Tax Engine

enum TaxEngine {
    static func calculateParts(situation: FamilySituation, children: Int) -> Double {
        var parts: Double = situation == .couple ? 2.0 : 1.0
        if situation == .singleParent { parts += 0.5 }
        if children <= 2 {
            parts += Double(children) * 0.5
        } else {
            parts += 1.0 + Double(children - 2)
        }
        return parts
    }

    static func taxForQuotient(_ q: Double, config: TaxConfig) -> (tax: Double, rate: Double, details: [TaxBracketDetail]) {
        var tax = 0.0
        var prev = 0.0
        var marginal = 0.0
        var details: [TaxBracketDetail] = []

        for b in config.brackets {
            let upper = b.upperBound ?? .infinity
            guard q > prev else { break }
            let taxable = min(q, upper) - prev
            let amount = taxable * b.rate
            tax += amount
            marginal = b.rate

            let label = upper == .infinity
                ? "Au-delà de \(cur(prev))"
                : "\(cur(prev)) → \(cur(upper))"
            details.append(.init(range: label, rate: b.rate, amount: amount))
            prev = upper
        }
        return (tax, marginal, details)
    }

    static func netImposable(_ gross: Double, config: TaxConfig) -> Double {
        guard gross > 0 else { return gross }
        let d = config.deduction
        let deduction = min(max(gross * d.rate, d.min), d.max)
        return max(0, gross - deduction)
    }

    static func emploiDomicileCap(children: Int, config: TaxConfig) -> Double {
        let c = config.credits.emploiDomicile
        return min(c.baseCap + Double(children) * c.perChildBonus, c.maxCap)
    }

    static func calculate(income: Double, situation: FamilySituation, children: Int,
                          emploiDomicile: Double = 0, donsAide: Double = 0, donsAutres: Double = 0,
                          config: TaxConfig = .default) -> TaxResult {
        let parts = calculateParts(situation: situation, children: children)
        let quotient = income / parts
        let (taxPerPart, marginal, details) = taxForQuotient(quotient, config: config)
        var taxBrut = taxPerPart * parts

        // Plafonnement du quotient familial
        var plafonnement = 0.0
        let baseParts: Double = situation == .couple ? 2.0 : 1.0
        let extraHalfParts = (parts - baseParts) * 2

        if extraHalfParts > 0 {
            let baseQ = income / baseParts
            let baseTax = taxForQuotient(baseQ, config: config).tax * baseParts

            let maxAdvantage: Double
            if situation == .singleParent && children > 0 {
                maxAdvantage = config.ceilingParentIsole + max(0, extraHalfParts - 2) * config.ceilingPerHalfPart
            } else {
                maxAdvantage = extraHalfParts * config.ceilingPerHalfPart
            }

            let advantage = baseTax - taxBrut
            if advantage > maxAdvantage {
                plafonnement = advantage - maxAdvantage
                taxBrut = baseTax - maxAdvantage
            }
        }

        // Décote
        var decote = 0.0
        let isCouple = situation == .couple
        let dc = config.decote
        let threshold = isCouple ? dc.coupleThreshold : dc.singleThreshold
        let forfait = isCouple ? dc.coupleForfait : dc.singleForfait

        if taxBrut > 0 && taxBrut <= threshold {
            decote = max(0, forfait - dc.coefficient * taxBrut)
            decote = min(decote, taxBrut)
        }

        let net = max(0, taxBrut - decote)

        // Crédits d'impôt
        let cr = config.credits
        let capEmploi = emploiDomicileCap(children: children, config: config)
        let creditEmploi = min(emploiDomicile, capEmploi) * cr.emploiDomicile.rate

        let creditAide = min(donsAide, cr.donsAide.cap) * cr.donsAide.rate

        let capDonsAutres = income > 0 ? income * cr.donsAutres.incomePercentCap : 0
        let creditAutres = min(donsAutres, capDonsAutres) * cr.donsAutres.rate

        let totalCredits = creditEmploi + creditAide + creditAutres
        let afterCredits = max(0, net - totalCredits)

        let avg = income > 0 ? (afterCredits / income) * 100 : 0

        return TaxResult(
            parts: parts,
            quotientFamilial: quotient,
            taxBrut: taxBrut,
            plafonnement: plafonnement,
            decote: decote,
            taxNet: net,
            creditEmploiDomicile: creditEmploi,
            creditDonsAide: creditAide,
            creditDonsAutres: creditAutres,
            taxAfterCredits: afterCredits,
            marginalRate: marginal * 100,
            averageRate: avg,
            brackets: details
        )
    }

    static func cur(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v)) €"
    }

    static func pct(_ v: Double) -> String {
        String(format: "%.2f %%", v)
    }
}

// MARK: - Km Allowance Calculator

enum VehicleType: String, CaseIterable, Identifiable {
    case car = "Voiture"
    case moto = "Moto (> 50 cm³)"
    case scooter = "Cyclomoteur (≤ 50 cm³)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .car: "car.fill"
        case .moto: "bicycle"
        case .scooter: "scooter"
        }
    }
}

enum KmBareme {
    static func label(config: KmAllowanceConfig) -> String {
        "Barème officiel \(config.scaleYear) (revenus \(config.revenueYear))."
    }

    struct Tier {
        let maxKm: Int     // upper bound of this tier (Int.max = no limit)
        let coeff: Double  // d × coeff
        let constant: Double // + constant
    }

    static func calculate(vehicleType: VehicleType, cv: Int, km: Int, config: KmAllowanceConfig) -> Double {
        let d = Double(km)
        let tiers = tiers(for: vehicleType, cv: cv, config: config)
        for tier in tiers {
            if km <= tier.maxKm {
                return d * tier.coeff + tier.constant
            }
        }
        return 0
    }

    private static func tiers(for type: VehicleType, cv: Int, config: KmAllowanceConfig) -> [Tier] {
        let selectedBand = band(for: type, cv: cv, config: config)
        return selectedBand.tiers.map { t in
            Tier(maxKm: t.maxKm ?? .max, coeff: t.coeff, constant: t.constant)
        }
    }

    static func cvRange(for type: VehicleType, config: KmAllowanceConfig) -> ClosedRange<Int> {
        let bands = vehicleConfig(for: type, config: config).bands
        let minCV = bands.map { $0.minCV }.min() ?? 1
        let maxCV = bands.map { $0.maxCV }.max() ?? 1
        return minCV...maxCV
    }

    static func cvLabel(for type: VehicleType, cv: Int, config: KmAllowanceConfig) -> String {
        band(for: type, cv: cv, config: config).label
    }

    private static func vehicleConfig(for type: VehicleType, config: KmAllowanceConfig) -> KmVehicleConfig {
        switch type {
        case .car: return config.car
        case .moto: return config.moto
        case .scooter: return config.scooter
        }
    }

    private static func band(for type: VehicleType, cv: Int, config: KmAllowanceConfig) -> KmBandConfig {
        let bands = vehicleConfig(for: type, config: config).bands
        if let match = bands.first(where: { cv >= $0.minCV && cv <= $0.maxCV }) {
            return match
        }
        return bands.first ?? KmAllowanceConfig.default.car.bands[0]
    }
}

struct KmCalculatorView: View {
    let kmConfig: KmAllowanceConfig
    let onUse: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var vehicleType: VehicleType = .car
    @State private var cv = 5
    @State private var kmText = ""

    private var km: Int { Int(kmText.replacingOccurrences(of: " ", with: "")) ?? 0 }
    private var amount: Double { KmBareme.calculate(vehicleType: vehicleType, cv: cv, km: km, config: kmConfig) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Véhicule") {
                    Picker("Type", selection: $vehicleType) {
                        ForEach(VehicleType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                    if vehicleType != .scooter {
                        Stepper(value: $cv, in: KmBareme.cvRange(for: vehicleType, config: kmConfig)) {
                            HStack {
                                Text("Puissance fiscale")
                                Spacer()
                                Text(KmBareme.cvLabel(for: vehicleType, cv: cv, config: kmConfig))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Distance") {
                    HStack {
                        TextField("ex : 12 000", text: $kmText)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                        Text("km / an")
                            .foregroundStyle(.secondary)
                    }
                }

                if km > 0 {
                    Section("Résultat") {
                        HStack {
                            Text("Indemnités kilométriques")
                            Spacer()
                            Text(TaxEngine.cur(amount))
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Label("\(KmBareme.label(config: kmConfig)) Ce montant inclut : carburant, entretien, assurance, dépréciation.", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            onUse(amount)
                            dismiss()
                        } label: {
                            Label("Utiliser ce montant", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
            }
            .navigationTitle("Frais km \(kmConfig.scaleYear)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onChange(of: vehicleType) { _, _ in
                let range = KmBareme.cvRange(for: vehicleType, config: kmConfig)
                if cv < range.lowerBound { cv = range.lowerBound }
                if cv > range.upperBound { cv = range.upperBound }
            }
        }
    }
}

// MARK: - View

struct ContentView: View {
    @State private var configLoader = TaxConfigLoader()
    @State private var incomeText1 = ""
    @State private var incomeText2 = ""
    @State private var deductionType1: DeductionType = .abattement
    @State private var deductionType2: DeductionType = .abattement
    @State private var fraisReelsText1 = ""
    @State private var fraisReelsText2 = ""
    @State private var sourceText1 = ""
    @State private var sourceText2 = ""
    @State private var situation: FamilySituation = .single
    @State private var children = 0
    @State private var emploiDomicileText = ""
    @State private var donsAideText = ""
    @State private var donsAutresText = ""
    @State private var result: TaxResult?
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var showScanResult = false
    @State private var scanDeclarant = 1
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scanProcessing = false
    @State private var scanResult: ExtractedTaxData?
    @State private var pendingScanData: [Data]?
    @State private var openAIKey: String = AITaxParser.apiKey
    @State private var showKmCalculator: KmTarget?
    @State private var showBracketDetail: BracketDetailData?
    @State private var showDecoteDetail = false
    @State private var showQuotientDetail = false
    @State private var showCalculator = false
    @State private var selectedCreditHelp: CreditHelpTopic?
    @State private var additionalEntries: [AdditionalTaxEntry] = []
    @State private var taxChatInput = ""
    @State private var taxChatMessages: [TaxChatMessage] = [
        .init(role: .assistant, text: "Décrivez votre situation (ex: pension alimentaire versée, revenus fonciers, frais de garde...). Je proposerai les cases à ajouter.")
    ]
    @State private var chatIsLoading = false
    @State private var pdfPreviewItem: TaxPDFPreviewItem?
    @State private var a4OptimizedPrint = false

    struct BracketDetailData: Identifiable {
        let id = UUID()
        let grossAmount: Double
        let netAmount: Double
        let deductionLabel: String
        let deductionAmount: Double
    }

    enum KmTarget: Identifiable {
        case declarant1, declarant2
        var id: Int { self == .declarant1 ? 1 : 2 }
    }

    private var config: TaxConfig { configLoader.config }
    private var kmConfig: KmAllowanceConfig { config.kmAllowance ?? .default }

    private var frequentTemplates: [FrequentTaxTemplate] {
        [
            .init(title: "Pension alimentaire versée", box: "6GU", kind: .deductibleCharge, note: "Charge déductible selon conditions"),
            .init(title: "Frais de garde enfants", box: "7GA", kind: .taxCredit, note: "Crédit d'impôt garde d'enfants"),
            .init(title: "Revenus fonciers", box: "4BA", kind: .taxableIncome, note: "Revenus locatifs imposables"),
            .init(title: "Travaux déductibles (foncier)", box: "4BC", kind: .deductibleCharge, note: "Charges/travaux selon régime"),
            .init(title: "Dons associations", box: "7UF", kind: .taxCredit, note: "Réduction/Crédit selon organisme"),
            .init(title: "Prélèvements déjà versés", box: "8HV", kind: .withholdingPaid, note: "Montants déjà payés à déduire")
        ]
    }

    @FocusState private var focusedField: Field?

    enum Field: Hashable { case income1, income2, fraisReels1, fraisReels2, source1, source2, emploi, donsAide, donsAutres }

    enum DeductionType: Int, CaseIterable {
        case abattement = 0    // Standard 10% deduction
        case fraisReels = 1    // User specifies actual expenses
    }

    private func parseAmount(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: "")  // non-breaking space
            .replacingOccurrences(of: "\u{202F}", with: "")  // narrow no-break space
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }

    private func netImposable(_ gross: Double, deductionType: DeductionType, fraisReels: Double = 0) -> Double {
        switch deductionType {
        case .fraisReels:
            return max(0, gross - fraisReels)
        case .abattement:
            return TaxEngine.netImposable(gross, config: config)
        }
    }

    private var salaryIncome: Double {
        let a = netImposable(parseAmount(incomeText1), deductionType: deductionType1, fraisReels: parseAmount(fraisReelsText1))
        let b = situation == .couple ? netImposable(parseAmount(incomeText2), deductionType: deductionType2, fraisReels: parseAmount(fraisReelsText2)) : 0
        return a + b
    }

    private var additionalTaxableIncome: Double {
        additionalEntries
            .filter { $0.kind == .taxableIncome }
            .reduce(0) { $0 + parseAmount($1.amountText) }
    }

    private var additionalDeductibleCharges: Double {
        additionalEntries
            .filter { $0.kind == .deductibleCharge }
            .reduce(0) { $0 + parseAmount($1.amountText) }
    }

    private var additionalTaxCredits: Double {
        additionalEntries
            .filter { $0.kind == .taxCredit }
            .reduce(0) { $0 + parseAmount($1.amountText) }
    }

    private var additionalWithholdingPaid: Double {
        additionalEntries
            .filter { $0.kind == .withholdingPaid }
            .reduce(0) { $0 + parseAmount($1.amountText) }
    }

    private var adjustedIncome: Double {
        max(0, salaryIncome + additionalTaxableIncome - additionalDeductibleCharges)
    }

    private var totalWithholding: Double {
        let s1 = parseAmount(sourceText1)
        let s2 = situation == .couple ? parseAmount(sourceText2) : 0
        return s1 + s2 + additionalWithholdingPaid
    }

    private var deductionTotal: Double {
        let g1 = parseAmount(incomeText1)
        let g2 = situation == .couple ? parseAmount(incomeText2) : 0
        let n1 = netImposable(g1, deductionType: deductionType1, fraisReels: parseAmount(fraisReelsText1))
        let n2 = netImposable(g2, deductionType: deductionType2, fraisReels: parseAmount(fraisReelsText2))
        return (g1 - n1) + (g2 - n2)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    configCard
                    scanCard
                    inputCard
                    creditsCard
                    taxAssistantCard
                    additionalEntriesCard
                    calculateButton
                    if let result { resultCards(result) }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Impôt \(config.year)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCalculator = true
                    } label: {
                        Label("Calculatrice", systemImage: "plus.forwardslash.minus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await configLoader.forceRefresh() }
                    } label: {
                        if configLoader.isLoading {
                            ProgressView()
                        } else {
                            Label("Actualiser le barème", systemImage: "arrow.clockwise.icloud")
                        }
                    }
                    .disabled(configLoader.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        preparePDFPreview()
                    } label: {
                        Label("Exporter PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onTapGesture { focusedField = nil }
            .task { await configLoader.load() }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCameraView { imageDataArray in
                    pendingScanData = imageDataArray
                } onDismiss: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: showCamera) { old, new in
                // Process scanned images AFTER camera is fully dismissed
                if old && !new, let dataArray = pendingScanData {
                    pendingScanData = nil
                    let images = dataArray.compactMap { UIImage(data: $0) }
                    guard !images.isEmpty else { return }
                    Task { await processScanImages(images) }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await processFileURL(url) }
                case .failure:
                    break
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await processPhotoItem(item) }
            }
            .sheet(isPresented: $showScanResult) {
                if let data = scanResult {
                    ScanResultView(data: data) {
                        applyExtractedData(data, declarant: scanDeclarant)
                    }
                }
            }
            .sheet(item: $showKmCalculator) { target in
                KmCalculatorView(kmConfig: kmConfig) { amount in
                    let text = String(Int(amount))
                    if target == .declarant2 {
                        fraisReelsText2 = text
                    } else {
                        fraisReelsText1 = text
                    }
                }
            }
            .sheet(item: $showBracketDetail) { data in
                BracketDetailSheet(data: data, config: config)
            }
            .sheet(isPresented: $showCalculator) {
                MiniCalculatorView()
            }
            .sheet(isPresented: $showDecoteDetail) {
                if let result {
                    DecoteDetailSheet(
                        taxBrut: result.taxBrut,
                        decote: result.decote,
                        isCouple: situation == .couple,
                        config: config
                    )
                }
            }
            .sheet(isPresented: $showQuotientDetail) {
                if let result {
                    QuotientDetailSheet(
                        income: adjustedIncome,
                        situation: situation,
                        children: children,
                        result: result,
                        config: config
                    )
                }
            }
            .sheet(item: $selectedCreditHelp) { topic in
                CreditHelpSheet(topic: topic, children: children, income: adjustedIncome, config: config)
            }
            .sheet(item: $pdfPreviewItem) { item in
                TaxPDFPreviewSheet(pdfURL: item.url, pdfData: item.data, isA4Optimized: item.isA4Optimized)
            }
            .overlay {
                if scanProcessing {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Analyse en cours\u{2026}")
                                    .foregroundStyle(.white)
                                    .font(.callout)
                            }
                            .padding(30)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                }
            }
        }
    }

    // MARK: - Scan Processing

    private func processScanImages(_ images: [UIImage]) async {
        scanProcessing = true
        var allText = ""
        for img in images {
            allText += await OCREngine.recognizeText(from: img) + "\n"
        }
        // Try AI parser first, fallback to regex
        if let aiResult = await AITaxParser.parse(text: allText) {
            scanResult = aiResult
        } else {
            scanResult = TaxDocumentParser.parse(text: allText)
        }
        scanProcessing = false
        showScanResult = true
    }

    private func processPhotoItem(_ item: PhotosPickerItem) async {
        scanProcessing = true
        defer { scanProcessing = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let text = await OCREngine.recognizeText(from: image)
        if let aiResult = await AITaxParser.parse(text: text) {
            scanResult = aiResult
        } else {
            scanResult = TaxDocumentParser.parse(text: text)
        }
        selectedPhoto = nil
        showScanResult = true
    }

    private func processFileURL(_ url: URL) async {
        scanProcessing = true
        defer { scanProcessing = false }
        let accessing = url.startAccessingSecurityScopedResource()

        // Copy to temp to release security scope before async work
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempURL)
        guard let _ = try? FileManager.default.copyItem(at: url, to: tempURL) else {
            if accessing { url.stopAccessingSecurityScopedResource() }
            return
        }
        if accessing { url.stopAccessingSecurityScopedResource() }

        if tempURL.pathExtension.lowercased() == "pdf" {
            let text = await OCREngine.ocrPDF(url: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
            guard !text.isEmpty else { return }
            if let aiResult = await AITaxParser.parse(text: text) {
                scanResult = aiResult
            } else {
                scanResult = TaxDocumentParser.parse(text: text)
            }
            showScanResult = true
        } else if let data = try? Data(contentsOf: tempURL), let img = UIImage(data: data) {
            try? FileManager.default.removeItem(at: tempURL)
            await processScanImages([img])
        } else {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func applyExtractedData(_ data: ExtractedTaxData, declarant: Int) {
        let incomeValue: Double?
        let deductionType: DeductionType

        if data.sourceType == .avisImposition {
            let net = data.revenuNetImposable
            let brut = data.revenuBrut

            if let net, let brut, brut > 0, net > 0 {
                if net >= brut * 0.5 {
                    // Already after deduction — use frais réels with 0 to pass through
                    incomeValue = net
                    deductionType = .fraisReels
                } else {
                    incomeValue = brut
                    deductionType = .abattement
                }
            } else if let brut, brut > 0 {
                incomeValue = brut
                deductionType = .abattement
            } else if let net, net > 0 {
                incomeValue = net
                deductionType = .fraisReels
            } else {
                incomeValue = nil
                deductionType = .abattement
            }
        } else if let net = data.revenuNetImposable {
            incomeValue = net
            deductionType = .fraisReels
        } else if let brut = data.revenuBrut {
            incomeValue = brut
            deductionType = .abattement
        } else {
            incomeValue = nil
            deductionType = .abattement
        }

        if let incomeValue {
            let text = String(Int(incomeValue))
            if declarant == 2 {
                deductionType2 = deductionType
                incomeText2 = text
                if deductionType == .fraisReels { fraisReelsText2 = "" }
            } else {
                deductionType1 = deductionType
                incomeText1 = text
                if deductionType == .fraisReels { fraisReelsText1 = "" }
            }
        }
        // Only update situation/children from declarant 1 or single
        if declarant == 1 {
            if let s = data.situation {
                situation = s
            }
            if let p = data.parts {
                let baseParts: Double = situation == .couple ? 2.0 : 1.0
                let extra = p - baseParts
                if extra > 0 {
                    if extra <= 1.0 {
                        children = Int(extra * 2)
                    } else {
                        children = Int(extra + 1)
                    }
                } else {
                    children = 0
                }
            }
        }
    }

    // MARK: - Config Card

    // MARK: - Scan Card

    private var scanCard: some View {
        VStack(spacing: 8) {
            if situation == .couple {
                Text("Scanner un document")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                Picker("Déclarant", selection: $scanDeclarant) {
                    Text("Déclarant 1").tag(1)
                    Text("Déclarant 2").tag(2)
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: 8) {
                Button {
                    showCamera = true
                } label: {
                    scanOptionLabel("Caméra", icon: "camera.fill")
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    scanOptionLabel("Photo", icon: "photo.on.rectangle")
                }

                Button {
                    showFilePicker = true
                } label: {
                    scanOptionLabel("PDF", icon: "doc.fill")
                }
            }

            // OpenAI API key for AI-powered parsing
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: openAIKey.isEmpty ? "brain" : "brain.fill")
                        .foregroundStyle(openAIKey.isEmpty ? Color.secondary : Color.green)
                    Text(openAIKey.isEmpty ? "Analyse IA désactivée" : "Analyse IA active")
                        .font(.caption)
                        .foregroundStyle(openAIKey.isEmpty ? Color.secondary : Color.green)
                    Spacer()
                }
                SecureField("Clé API OpenAI", text: $openAIKey)
                    .textContentType(.password)
                    .font(.caption)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: openAIKey) { _, newValue in
                        AITaxParser.apiKey = newValue
                    }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private func scanOptionLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .foregroundStyle(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Config Card

    private var configCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: configLoader.isRemote ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.title2)
                    .foregroundStyle(configLoader.isRemote ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.label)
                        .font(.subheadline.weight(.semibold))
                    if let date = configLoader.lastUpdate {
                        Text("Dernière synchro : \(date.formatted(.dateTime.day().month().year().hour().minute()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Barème par défaut (intégré)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            // Refresh result feedback
            if let result = configLoader.refreshResult {
                HStack(spacing: 6) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Barème mis à jour !")
                    case .noChange:
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("Déjà à jour")
                    case .error(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                    }
                }
                .font(.caption)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task {
                    configLoader.refreshResult = nil
                    await configLoader.forceRefresh()
                }
            } label: {
                HStack {
                    if configLoader.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise.icloud")
                    }
                    Text(configLoader.isLoading ? "Vérification…" : "Vérifier les mises à jour")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(configLoader.isLoading ? 0.5 : 1))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(configLoader.isLoading)

            Toggle(isOn: $a4OptimizedPrint) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode impression A4 optimisée")
                        .font(.subheadline.weight(.semibold))
                    Text("Marges compactes + police légèrement réduite pour le PDF")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Link(destination: URL(string: "https://www.service-public.gouv.fr/particuliers/vosdroits/F1419")!) {
                HStack {
                    Image(systemName: "safari")
                    Text("Voir le barème officiel")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Link(destination: URL(string: "https://boboul-cloud.github.io/tax-config/")!) {
                HStack {
                    Image(systemName: "pencil.circle")
                    Text("Modifier le barème en ligne")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .animation(.easeInOut, value: configLoader.refreshResult != nil)
    }

    // MARK: - Input Card

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Votre situation", systemImage: "person.text.rectangle")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Declarant 1
            declarantIncomeSection(
                declarant: situation == .couple ? 1 : nil,
                incomeText: $incomeText1,
                deductionType: $deductionType1,
                fraisReelsText: $fraisReelsText1,
                sourceText: $sourceText1,
                incomeFieldTag: .income1,
                fraisFieldTag: .fraisReels1,
                sourceFieldTag: .source1,
                kmTarget: .declarant1
            )

            // Declarant 2
            if situation == .couple {
                Divider()
                declarantIncomeSection(
                    declarant: 2,
                    incomeText: $incomeText2,
                    deductionType: $deductionType2,
                    fraisReelsText: $fraisReelsText2,
                    sourceText: $sourceText2,
                    incomeFieldTag: .income2,
                    fraisFieldTag: .fraisReels2,
                    sourceFieldTag: .source2,
                    kmTarget: .declarant2
                )
            }

            // Summary after deduction
            if salaryIncome > 0 || additionalTaxableIncome > 0 || additionalDeductibleCharges > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if deductionTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Déductions : −\(TaxEngine.cur(deductionTotal))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    if additionalTaxableIncome > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Autres revenus : +\(TaxEngine.cur(additionalTaxableIncome))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    if additionalDeductibleCharges > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Autres charges déductibles : −\(TaxEngine.cur(additionalDeductibleCharges))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Revenu net imposable retenu : \(TaxEngine.cur(adjustedIncome))")
                            .fontWeight(.medium)
                    }
                    .font(.footnote)
                }
            }

            // Situation
            VStack(alignment: .leading, spacing: 8) {
                Text("Situation familiale")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(FamilySituation.allCases) { s in
                        Button {
                            situation = s
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: s.icon)
                                    .font(.callout)
                                Text(s.rawValue)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(situation == s ? Color.blue : Color(.systemGray5))
                            .foregroundStyle(situation == s ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }

            // Children
            VStack(alignment: .leading, spacing: 8) {
                Text("Enfants à charge")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    ForEach(0...5, id: \.self) { n in
                        Button {
                            children = n
                        } label: {
                            Text("\(n)")
                                .font(.callout.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(children == n ? Color.blue : Color(.systemGray5))
                                .foregroundStyle(children == n ? .white : .primary)
                                .clipShape(Circle())
                        }
                    }
                }
            }

            // Parts
            let parts = TaxEngine.calculateParts(situation: situation, children: children)
            HStack {
                Image(systemName: "person.2.circle")
                    .foregroundStyle(.blue)
                Text("Nombre de parts :")
                    .foregroundStyle(.secondary)
                Text(formatParts(parts))
                    .fontWeight(.semibold)
            }
            .font(.callout)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // MARK: - Credits Card

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Crédits d'impôt", systemImage: "hand.thumbsup.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Emploi à domicile (dépenses)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $emploiDomicileText, field: .emploi)
                creditMetaRow(topic: .emploiDomicile)
                Label("Crédit de \(Int(config.credits.emploiDomicile.rate * 100)) % — Plafond \(TaxEngine.cur(TaxEngine.emploiDomicileCap(children: children, config: config)))", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dons — aide aux personnes en difficulté")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $donsAideText, field: .donsAide)
                creditMetaRow(topic: .donsAide)
                Label("Réduction de \(Int(config.credits.donsAide.rate * 100)) % — Plafond \(TaxEngine.cur(config.credits.donsAide.cap))", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dons — autres organismes d'intérêt général")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $donsAutresText, field: .donsAutres)
                creditMetaRow(topic: .donsAutres)
                Label("Réduction de \(Int(config.credits.donsAutres.rate * 100)) % — Plafond \(Int(config.credits.donsAutres.incomePercentCap * 100)) % du revenu", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private func creditMetaRow(topic: CreditHelpTopic) -> some View {
        HStack(spacing: 8) {
            Label("Case déclaration: \(topic.declarationBox)", systemImage: "doc.text")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                selectedCreditHelp = topic
            } label: {
                Label("Explication", systemImage: "questionmark.circle")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
    }

    // MARK: - Calculate Button

    private var calculateButton: some View {
        Button {
            focusedField = nil
            guard adjustedIncome > 0 else { return }
            withAnimation(.spring(duration: 0.4)) {
                let baseResult = TaxEngine.calculate(
                    income: adjustedIncome,
                    situation: situation,
                    children: children,
                    emploiDomicile: parseAmount(emploiDomicileText),
                    donsAide: parseAmount(donsAideText),
                    donsAutres: parseAmount(donsAutresText),
                    config: config
                )

                let finalAfterAdditionalCredits = max(0, baseResult.taxAfterCredits - additionalTaxCredits)
                let finalAverageRate = adjustedIncome > 0 ? (finalAfterAdditionalCredits / adjustedIncome) * 100 : 0

                result = TaxResult(
                    parts: baseResult.parts,
                    quotientFamilial: baseResult.quotientFamilial,
                    taxBrut: baseResult.taxBrut,
                    plafonnement: baseResult.plafonnement,
                    decote: baseResult.decote,
                    taxNet: baseResult.taxNet,
                    creditEmploiDomicile: baseResult.creditEmploiDomicile,
                    creditDonsAide: baseResult.creditDonsAide,
                    creditDonsAutres: baseResult.creditDonsAutres,
                    taxAfterCredits: finalAfterAdditionalCredits,
                    marginalRate: baseResult.marginalRate,
                    averageRate: finalAverageRate,
                    brackets: baseResult.brackets
                )
            }
        } label: {
            HStack {
                Image(systemName: "eurosign.circle.fill")
                Text("Calculer l'impôt")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Result Cards

    @ViewBuilder
    private func resultCards(_ r: TaxResult) -> some View {
        // Main result
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                let remainder = totalWithholding > 0 ? r.taxAfterCredits - totalWithholding : r.taxAfterCredits
                Text(totalWithholding > 0
                     ? (remainder >= 0 ? "Reste à payer" : "Trop-perçu")
                     : "Impôt à payer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(TaxEngine.cur(abs(remainder)))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        remainder < 0
                        ? LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                if totalWithholding > 0 {
                    Text("Impôt total : \(TaxEngine.cur(r.taxAfterCredits))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if r.taxAfterCredits > 0 {
                    Text("\(TaxEngine.cur(r.taxAfterCredits / 12)) / mois")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 0) {
                metric("TMI", value: TaxEngine.pct(r.marginalRate), icon: "chart.bar.fill")
                Divider().frame(height: 40)
                metric("Taux moyen", value: TaxEngine.pct(r.averageRate), icon: "percent")
                Divider().frame(height: 40)
                Button {
                    showQuotientDetail = true
                } label: {
                    metric("Quotient", value: TaxEngine.cur(r.quotientFamilial), icon: "divide.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

        // Detail
        VStack(alignment: .leading, spacing: 16) {
            Label("Détail du calcul", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Barème progressif (sur le quotient familial)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                ForEach(Array(r.brackets.enumerated()), id: \.offset) { _, b in
                    HStack {
                        Text(b.range)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(b.rate * 100)) %")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                        Text(TaxEngine.cur(b.amount))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }

            Divider()

            row("Impôt brut (× \(formatParts(r.parts)) parts)", value: r.taxBrut)

            if r.plafonnement > 0 {
                row("Plafonnement du QF", value: r.plafonnement, color: .orange, prefix: "+")
            }

            if r.decote > 0 {
                Button {
                    showDecoteDetail = true
                } label: {
                    HStack {
                        Text("Décote")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Spacer()
                        Text("−\(TaxEngine.cur(r.decote))")
                            .font(.callout.weight(.medium).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                .buttonStyle(.plain)
            }

            row("Impôt après décote", value: r.taxNet)

            if r.creditEmploiDomicile > 0 {
                creditDetailRow(
                    title: "Crédit emploi à domicile (\(Int(config.credits.emploiDomicile.rate * 100)) %)",
                    value: r.creditEmploiDomicile,
                    topic: .emploiDomicile
                )
            }

            if r.creditDonsAide > 0 {
                creditDetailRow(
                    title: "Réduction dons aide (\(Int(config.credits.donsAide.rate * 100)) %)",
                    value: r.creditDonsAide,
                    topic: .donsAide
                )
            }

            if r.creditDonsAutres > 0 {
                creditDetailRow(
                    title: "Réduction dons organismes (\(Int(config.credits.donsAutres.rate * 100)) %)",
                    value: r.creditDonsAutres,
                    topic: .donsAutres
                )
            }

            if additionalTaxCredits > 0 {
                row("Autres crédits/réductions", value: additionalTaxCredits, color: .green, prefix: "−")
            }

            Divider()

            HStack {
                Text("Impôt net")
                    .fontWeight(.semibold)
                Spacer()
                Text(TaxEngine.cur(r.taxAfterCredits))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.blue)
            }

            if totalWithholding > 0 {
                Divider()

                row("Prélèvement à la source déjà réglé", value: totalWithholding, color: .green, prefix: "−")

                let remainder = r.taxAfterCredits - totalWithholding
                HStack {
                    Text(remainder >= 0 ? "Reste à payer" : "Trop-perçu (remboursement)")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(TaxEngine.cur(abs(remainder)))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(remainder >= 0 ? .orange : .green)
                }
            }

            HStack(spacing: 4) {
                Text("\(config.label) (\(config.legalReference))")
                if configLoader.isRemote {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private func creditDetailRow(title: String, value: Double, topic: CreditHelpTopic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row(title, value: value, color: .green, prefix: "−")
            HStack(spacing: 8) {
                Text("Case déclaration: \(topic.declarationBox)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    selectedCreditHelp = topic
                } label: {
                    Label("Explication", systemImage: "questionmark.circle")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            .padding(.leading, 2)
        }
    }

    // MARK: - Declarant Section

    private var taxAssistantCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Assistant fiscal IA", systemImage: "message.and.waveform")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Décrivez votre situation pour proposer automatiquement des cases à remplir.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taxChatMessages) { message in
                        chatBubble(message)
                    }
                }
            }
            .frame(maxHeight: 180)

            HStack(spacing: 8) {
                TextField("Ex: J'ai versé une pension et j'ai des revenus locatifs", text: $taxChatInput)
                    .textFieldStyle(.roundedBorder)

                Button {
                    sendTaxChatPrompt()
                } label: {
                    if chatIsLoading {
                        ProgressView()
                            .frame(width: 30)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 30)
                    }
                }
                .disabled(chatIsLoading || taxChatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private var additionalEntriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Autres entrées fiscales", systemImage: "square.and.pencil")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    additionalEntries.append(.init(title: "Nouvelle entrée", suggestedBox: "", kind: .deductibleCharge))
                } label: {
                    Label("Ajouter", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(frequentTemplates) { template in
                        Button {
                            addTemplateEntry(template)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(template.box)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(template.kind.tint.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if additionalEntries.isEmpty {
                Text("Aucune entrée ajoutée. Utilisez l'assistant IA ci-dessus, ou ajoutez manuellement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach($additionalEntries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Libellé (ex: pension alimentaire)", text: $entry.title)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                removeAdditionalEntry(entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }

                        HStack {
                            Picker("Type", selection: $entry.kind) {
                                ForEach(AdditionalEntryKind.allCases) { kind in
                                    Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField("Case (ex: 6GU)", text: $entry.suggestedBox)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            TextField("Montant", text: $entry.amountText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            Text("€")
                                .foregroundStyle(.secondary)
                        }

                        if !entry.note.isEmpty {
                            Label(entry.note, systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private func sendTaxChatPrompt() {
        let prompt = taxChatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !chatIsLoading else { return }

        chatIsLoading = true
        taxChatInput = ""
        taxChatMessages.append(.init(role: .user, text: prompt))

        Task {
            let response = await AITaxFormAssistant.suggestEntries(query: prompt, apiKey: openAIKey)
            await MainActor.run {
                mergeAdditionalEntries(response.entries)
                let intro = response.entries.isEmpty
                    ? response.message
                    : "\(response.message) (\(response.entries.count) case\(response.entries.count > 1 ? "s" : "") ajoutée\(response.entries.count > 1 ? "s" : ""))."
                taxChatMessages.append(.init(role: .assistant, text: intro))
                chatIsLoading = false
            }
        }
    }

    private func mergeAdditionalEntries(_ entries: [AdditionalTaxEntry]) {
        for entry in entries {
            let exists = additionalEntries.contains {
                $0.kind == entry.kind
                && $0.title.caseInsensitiveCompare(entry.title) == .orderedSame
                && $0.suggestedBox.caseInsensitiveCompare(entry.suggestedBox) == .orderedSame
            }
            if !exists {
                additionalEntries.append(entry)
            }
        }
    }

    private func removeAdditionalEntry(_ id: UUID) {
        additionalEntries.removeAll { $0.id == id }
    }

    private func addTemplateEntry(_ template: FrequentTaxTemplate) {
        let exists = additionalEntries.contains {
            $0.title.caseInsensitiveCompare(template.title) == .orderedSame
            && $0.suggestedBox.caseInsensitiveCompare(template.box) == .orderedSame
            && $0.kind == template.kind
        }
        guard !exists else { return }
        additionalEntries.append(
            .init(
                title: template.title,
                suggestedBox: template.box,
                kind: template.kind,
                amountText: "",
                note: template.note
            )
        )
    }

    private func preparePDFPreview() {
        guard let pdf = createTaxSheetPDF() else { return }
        pdfPreviewItem = TaxPDFPreviewItem(url: pdf.url, data: pdf.data, isA4Optimized: a4OptimizedPrint)
    }

    private func createTaxSheetPDF() -> GeneratedTaxPDF? {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let now = Date()
        let taxResult = result
        let parts = taxResult?.parts ?? TaxEngine.calculateParts(situation: situation, children: children)
        let compact = a4OptimizedPrint

        struct PDFRow {
            let label: String
            let box: String
            let value: String
        }

        struct PDFSection {
            let title: String
            let rows: [PDFRow]
        }

        var sections: [PDFSection] = [
            PDFSection(
                title: "A. Situation du foyer fiscal",
                rows: [
                    PDFRow(label: "Situation familiale", box: "ETAT", value: situation.rawValue),
                    PDFRow(label: "Nombre d'enfants à charge", box: "F", value: "\(children)"),
                    PDFRow(label: "Nombre de parts fiscales", box: "PART", value: formatParts(parts))
                ]
            ),
            PDFSection(
                title: "B. Revenus imposables",
                rows: [
                    PDFRow(label: "Revenu imposable déclarant 1", box: "1AJ", value: TaxEngine.cur(netImposable(parseAmount(incomeText1), deductionType: deductionType1, fraisReels: parseAmount(fraisReelsText1)))),
                    PDFRow(label: "Revenu imposable déclarant 2", box: "1BJ", value: situation == .couple
                        ? TaxEngine.cur(netImposable(parseAmount(incomeText2), deductionType: deductionType2, fraisReels: parseAmount(fraisReelsText2)))
                        : "—"),
                    PDFRow(label: "Autres revenus imposables", box: "AUTR", value: TaxEngine.cur(additionalTaxableIncome)),
                    PDFRow(label: "Autres charges déductibles", box: "DEDU", value: "-\(TaxEngine.cur(additionalDeductibleCharges))"),
                    PDFRow(label: "Revenu net imposable retenu", box: "RNI", value: TaxEngine.cur(adjustedIncome))
                ]
            ),
            PDFSection(
                title: "C. Crédits / réductions / prélèvements",
                rows: [
                    PDFRow(label: "Emploi à domicile", box: "7DB", value: TaxEngine.cur(parseAmount(emploiDomicileText))),
                    PDFRow(label: "Dons aide aux personnes", box: "7UD", value: TaxEngine.cur(parseAmount(donsAideText))),
                    PDFRow(label: "Dons autres organismes", box: "7UF", value: TaxEngine.cur(parseAmount(donsAutresText))),
                    PDFRow(label: "Autres crédits/réductions", box: "CRED", value: TaxEngine.cur(additionalTaxCredits)),
                    PDFRow(label: "Prélèvements déjà versés", box: "PAS", value: TaxEngine.cur(totalWithholding))
                ]
            )
        ]

        if !additionalEntries.isEmpty {
            let rows = additionalEntries.map { entry in
                PDFRow(
                    label: entry.title,
                    box: entry.suggestedBox.isEmpty ? "--" : String(entry.suggestedBox.prefix(5)),
                    value: TaxEngine.cur(parseAmount(entry.amountText))
                )
            }
            sections.append(PDFSection(title: "D. Entrées complémentaires", rows: rows))
        }

        let resultRows: [PDFRow] = {
            if let taxResult {
                var rows: [PDFRow] = [
                    PDFRow(label: "Impôt brut", box: "BRUT", value: TaxEngine.cur(taxResult.taxBrut)),
                    PDFRow(label: "Décote", box: "DEC", value: "-\(TaxEngine.cur(taxResult.decote))"),
                    PDFRow(label: "Impôt net", box: "NET", value: TaxEngine.cur(taxResult.taxNet))
                ]
                if additionalTaxCredits > 0 {
                    rows.append(PDFRow(label: "Autres crédits/réductions", box: "CRED", value: "-\(TaxEngine.cur(additionalTaxCredits))"))
                }
                rows.append(PDFRow(label: "Impôt final après crédits", box: "FINAL", value: TaxEngine.cur(taxResult.taxAfterCredits)))
                let remainder = taxResult.taxAfterCredits - totalWithholding
                rows.append(PDFRow(label: remainder >= 0 ? "Reste à payer" : "Trop-perçu", box: "SOLDE", value: TaxEngine.cur(abs(remainder))))
                return rows
            }
            return [PDFRow(label: "État", box: "INFO", value: "Lancer le calcul avant export")]
        }()

        sections.append(PDFSection(title: "E. Résultat de la simulation", rows: resultRows))

        let data = renderer.pdfData { context in
            let margin: CGFloat = compact ? 18 : 26
            let fullWidth = pageRect.width - (margin * 2)
            let cg = context.cgContext
            let blue = UIColor(red: 0.11, green: 0.32, blue: 0.74, alpha: 1)
            let red = UIColor(red: 0.78, green: 0.14, blue: 0.14, alpha: 1)
            let pageBottom = pageRect.height - margin

            let titleFont = UIFont.systemFont(ofSize: compact ? 14 : 16, weight: .bold)
            let subtitleFont = UIFont.systemFont(ofSize: compact ? 8.5 : 9.5, weight: .regular)
            let headerFont = UIFont.systemFont(ofSize: compact ? 9.5 : 10.5, weight: .bold)
            let rowLabelFont = UIFont.systemFont(ofSize: compact ? 8.7 : 9.5, weight: .regular)
            let rowValueFont = UIFont.monospacedDigitSystemFont(ofSize: compact ? 8.8 : 9.8, weight: .semibold)

            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.black]
            let subtitleAttrs: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: UIColor.darkGray]
            let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: blue]
            let rowLabelAttrs: [NSAttributedString.Key: Any] = [.font: rowLabelFont, .foregroundColor: UIColor.black]
            let rowValueAttrs: [NSAttributedString.Key: Any] = [.font: rowValueFont, .foregroundColor: UIColor.black]
            let rowCodeAttrs: [NSAttributedString.Key: Any] = [.font: rowValueFont, .foregroundColor: red]

            let rowHeight: CGFloat = compact ? 17 : 20
            let sectionHeaderHeight: CGFloat = compact ? 16 : 18
            let titleBlockHeight: CGFloat = compact ? 46 : 56
            let footerHeight: CGFloat = compact ? 20 : 24
            let codeWidth: CGFloat = compact ? 50 : 56
            let valueWidth: CGFloat = compact ? 104 : 114
            var y: CGFloat = margin

            func strokeRect(_ rect: CGRect, color: UIColor, width: CGFloat = 0.9) {
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(width)
                cg.stroke(rect)
            }

            func drawPageSkeleton() {
                let frameRect = CGRect(x: margin, y: margin, width: fullWidth, height: pageRect.height - (margin * 2))
                strokeRect(frameRect, color: blue, width: 1.2)

                let iconRect = CGRect(x: margin + 8, y: y + 6, width: 16, height: 16)
                strokeRect(iconRect, color: red, width: 1.0)
                ("RF" as NSString).draw(in: CGRect(x: iconRect.minX + 2, y: iconRect.minY + 2, width: 12, height: 10), withAttributes: [
                    .font: UIFont.systemFont(ofSize: compact ? 6 : 7, weight: .bold),
                    .foregroundColor: red
                ])

                let titleRect = CGRect(x: margin + 30, y: y + 4, width: fullWidth - 38, height: titleBlockHeight - 8)
                strokeRect(titleRect, color: blue, width: 1.0)
                ("2042-SIM • Déclaration des revenus — Feuille de simulation" as NSString)
                    .draw(in: CGRect(x: titleRect.minX + 8, y: titleRect.minY + 5, width: titleRect.width - 16, height: 16), withAttributes: titleAttrs)
                ("Année \(config.year) • Revenus \(config.revenueYear) • Édité le \(now.formatted(.dateTime.day().month().year().hour().minute()))" as NSString)
                    .draw(in: CGRect(x: titleRect.minX + 8, y: titleRect.minY + (compact ? 21 : 24), width: titleRect.width - 16, height: 12), withAttributes: subtitleAttrs)
                y += titleBlockHeight + 6
            }

            func ensureSpace(_ needed: CGFloat, currentSection: String) {
                if y + needed > pageBottom - footerHeight {
                    context.beginPage()
                    y = margin
                    drawPageSkeleton()

                    let contRect = CGRect(x: margin, y: y, width: fullWidth, height: sectionHeaderHeight)
                    cg.setFillColor(UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1).cgColor)
                    cg.fill(contRect)
                    strokeRect(contRect, color: blue)
                    let marker = CGRect(x: contRect.minX, y: contRect.minY, width: 4, height: sectionHeaderHeight)
                    cg.setFillColor(red.cgColor)
                    cg.fill(marker)
                    ("\(currentSection) (suite)" as NSString)
                        .draw(in: CGRect(x: contRect.minX + 8, y: contRect.minY + 3, width: contRect.width - 12, height: 12), withAttributes: headerAttrs)
                    y += sectionHeaderHeight
                }
            }

            func drawSectionHeader(_ title: String) {
                ensureSpace(sectionHeaderHeight + rowHeight, currentSection: title)
                let rect = CGRect(x: margin, y: y, width: fullWidth, height: sectionHeaderHeight)
                cg.setFillColor(UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1).cgColor)
                cg.fill(rect)
                strokeRect(rect, color: blue)
                let marker = CGRect(x: rect.minX, y: rect.minY, width: 4, height: sectionHeaderHeight)
                cg.setFillColor(red.cgColor)
                cg.fill(marker)
                (title as NSString).draw(in: CGRect(x: rect.minX + 8, y: rect.minY + 3, width: rect.width - 12, height: 12), withAttributes: headerAttrs)
                y += sectionHeaderHeight
            }

            func drawRow(_ row: PDFRow, in sectionTitle: String) {
                ensureSpace(rowHeight, currentSection: sectionTitle)
                let labelRect = CGRect(x: margin, y: y, width: fullWidth - codeWidth - valueWidth, height: rowHeight)
                let codeRect = CGRect(x: labelRect.maxX, y: y, width: codeWidth, height: rowHeight)
                let valueRect = CGRect(x: codeRect.maxX, y: y, width: valueWidth, height: rowHeight)

                strokeRect(labelRect, color: blue)
                strokeRect(codeRect, color: red)
                strokeRect(valueRect, color: blue)

                (row.label as NSString).draw(in: CGRect(x: labelRect.minX + 6, y: y + 3, width: labelRect.width - 10, height: rowHeight - 6), withAttributes: rowLabelAttrs)
                (row.box as NSString).draw(in: CGRect(x: codeRect.minX + 5, y: y + 3, width: codeRect.width - 8, height: rowHeight - 6), withAttributes: rowCodeAttrs)
                (row.value as NSString).draw(in: CGRect(x: valueRect.minX + 5, y: y + 3, width: valueRect.width - 8, height: rowHeight - 6), withAttributes: rowValueAttrs)
                y += rowHeight
            }

            context.beginPage()
            drawPageSkeleton()

            for section in sections {
                drawSectionHeader(section.title)
                for row in section.rows {
                    drawRow(row, in: section.title)
                }
            }

            ensureSpace(footerHeight, currentSection: sections.last?.title ?? "Simulation")
            let footerRect = CGRect(x: margin, y: y + 2, width: fullWidth, height: footerHeight)
            strokeRect(footerRect, color: blue)
            ("Document de simulation non contractuel • Vérifier les cases officielles avant déclaration" as NSString)
                .draw(in: CGRect(x: footerRect.minX + 8, y: footerRect.minY + 5, width: footerRect.width - 12, height: 11), withAttributes: subtitleAttrs)
        }

        let fileName = "feuille_impot_\(config.year)_\(Int(now.timeIntervalSince1970)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return GeneratedTaxPDF(url: url, data: data)
        } catch {
            return nil
        }
    }

    @ViewBuilder
    private func chatBubble(_ message: TaxChatMessage) -> some View {
        let isAssistant = message.role == .assistant
        HStack {
            if isAssistant {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.blue)
            }

            Text(message.text)
                .font(.caption)
                .padding(10)
                .background(isAssistant ? Color(.systemGray6) : Color.blue)
                .foregroundStyle(isAssistant ? Color.primary : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if !isAssistant {
                Image(systemName: "person.fill")
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: isAssistant ? .leading : .trailing)
    }

    private func declarantIncomeSection(
        declarant: Int?,
        incomeText: Binding<String>,
        deductionType: Binding<DeductionType>,
        fraisReelsText: Binding<String>,
        sourceText: Binding<String>,
        incomeFieldTag: Field,
        fraisFieldTag: Field,
        sourceFieldTag: Field,
        kmTarget: KmTarget
    ) -> AnyView {
        let label = declarant.map { "Déclarant \($0)" } ?? ""
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Income
                VStack(alignment: .leading, spacing: 6) {
                    Text(declarant != nil ? "Net imposable — \(label)" : "Net imposable annuel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    incomeField(text: incomeText, field: incomeFieldTag)
                }

                // Deduction type picker
                VStack(alignment: .leading, spacing: 8) {
                    Picker(declarant != nil ? "Déduction — \(label)" : "Déduction", selection: deductionType) {
                        Text("Abattement 10 %").tag(DeductionType.abattement)
                        Text("Frais réels").tag(DeductionType.fraisReels)
                    }
                    .pickerStyle(.segmented)

                    if deductionType.wrappedValue == .abattement {
                        let d = config.deduction
                        Label("Abattement de \(Int(d.rate * 100)) % appliqué automatiquement (min \(TaxEngine.cur(d.min)), max \(TaxEngine.cur(d.max)))", systemImage: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                // Frais réels (if selected)
                if deductionType.wrappedValue == .fraisReels {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(declarant != nil ? "Frais réels — \(label)" : "Frais réels annuels")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showKmCalculator = kmTarget
                            } label: {
                                Label("Frais km", systemImage: "car.fill")
                                    .font(.caption)
                            }
                        }
                        incomeField(text: fraisReelsText, field: fraisFieldTag)
                    }
                }

                // Calculation breakdown
                deductionDetailView(
                    grossAmount: parseAmount(incomeText.wrappedValue),
                    deductionType: deductionType.wrappedValue,
                    fraisReels: parseAmount(fraisReelsText.wrappedValue)
                )

                // Withholding tax
                VStack(alignment: .leading, spacing: 6) {
                    Text(declarant != nil ? "Prélèvement à la source — \(label)" : "Prélèvement à la source déjà réglé")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    incomeField(text: sourceText, field: sourceFieldTag)

                    // Estimated withholding suggestion
                    withholdingSuggestion(
                        grossAmount: parseAmount(incomeText.wrappedValue),
                        deductionType: deductionType.wrappedValue,
                        fraisReels: parseAmount(fraisReelsText.wrappedValue),
                        sourceText: sourceText
                    )
                }
            }
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func withholdingSuggestion(grossAmount: Double, deductionType: DeductionType, fraisReels: Double, sourceText: Binding<String>) -> some View {
        let net = netImposable(grossAmount, deductionType: deductionType, fraisReels: fraisReels)
        if net > 0 {
            // Estimate individual tax (1 part, single, no credits) to derive a rate
            let estimatedResult = TaxEngine.calculate(
                income: net,
                situation: .single,
                children: 0,
                config: config
            )
            let estimatedAnnual = estimatedResult.taxAfterCredits
            let rate = estimatedAnnual / net
            let monthly = grossAmount / 12
            let monthlyWithholding = monthly * rate

            if estimatedAnnual > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Estimation du prélèvement à la source")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taux estimé : \(String(format: "%.1f", rate * 100)) %")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(TaxEngine.cur(monthlyWithholding)) / mois × 12 = \(TaxEngine.cur(monthlyWithholding * 12))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            sourceText.wrappedValue = String(Int(monthlyWithholding * 12))
                        } label: {
                            Text("Appliquer")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Label("Estimation indicative basée sur le barème individuel (1 part). Le taux réel dépend du foyer fiscal.", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func deductionDetailView(grossAmount: Double, deductionType: DeductionType, fraisReels: Double) -> some View {
        if grossAmount > 0 {
            let d = config.deduction
            let deductionAmount: Double = {
                switch deductionType {
                case .abattement:
                    return min(max(grossAmount * d.rate, d.min), d.max)
                case .fraisReels:
                    return fraisReels
                }
            }()
            let netAmount = max(0, grossAmount - deductionAmount)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "function")
                        .foregroundStyle(.blue)
                    Text("Détail du calcul")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Salaire déclaré")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(TaxEngine.cur(grossAmount))
                        .font(.caption.weight(.medium).monospacedDigit())
                }

                if deductionType == .abattement {
                    let rawDeduction = grossAmount * d.rate
                    let cappedInfo: String? = {
                        if rawDeduction < d.min { return "plancher \(TaxEngine.cur(d.min))" }
                        if rawDeduction > d.max { return "plafond \(TaxEngine.cur(d.max))" }
                        return nil
                    }()

                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Abattement \(Int(d.rate * 100)) %")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let info = cappedInfo {
                                Text(info)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text("−\(TaxEngine.cur(deductionAmount))")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                } else if fraisReels > 0 {
                    HStack {
                        Text("Frais réels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("−\(TaxEngine.cur(deductionAmount))")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                }

                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)

                HStack {
                    Text("Net imposable")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(TaxEngine.cur(netAmount))
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(.blue)
                }

                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 0.5)

                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.blue)
                    Text("Voir l'impôt par tranche")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                let deductionLabel = deductionType == .abattement ? "Abattement \(Int(d.rate * 100)) %" : "Frais réels"
                showBracketDetail = BracketDetailData(
                    grossAmount: grossAmount,
                    netAmount: netAmount,
                    deductionLabel: deductionLabel,
                    deductionAmount: deductionAmount
                )
            }
        }
    }

    private func incomeField(text: Binding<String>, field: Field) -> some View {
        HStack {
            TextField("ex : 35 000", text: text)
                .keyboardType(.decimalPad)
                .font(.title2.monospacedDigit())
                .focused($focusedField, equals: field)
            Text("€")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .font(.caption)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ label: String, value: Double, color: Color = .primary, prefix: String = "") -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(prefix)\(TaxEngine.cur(value))")
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func formatParts(_ p: Double) -> String {
        p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))" : String(format: "%.1f", p)
    }
}

struct TaxPDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        let currentPages = uiView.document?.pageCount ?? 0
        let nextPages = PDFDocument(data: data)?.pageCount ?? 0
        if currentPages != nextPages {
            uiView.document = PDFDocument(data: data)
        }
    }
}

struct TaxPDFPreviewSheet: View {
    let pdfURL: URL
    let pdfData: Data
    let isA4Optimized: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TaxPDFPreview(data: pdfData)
                    .background(Color(.systemBackground))

                if isA4Optimized {
                    HStack(spacing: 6) {
                        Image(systemName: "printer.fill")
                        Text("A4 optimisé")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.92))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(12)
                }
            }
            .navigationTitle("Aperçu PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: pdfURL) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Bracket Detail Sheet

struct BracketDetailSheet: View {
    let data: ContentView.BracketDetailData
    let config: TaxConfig
    @Environment(\.dismiss) private var dismiss

    private var brackets: [TaxBracketDetail] {
        TaxEngine.taxForQuotient(data.netAmount, config: config).details
    }

    private var totalTax: Double {
        TaxEngine.taxForQuotient(data.netAmount, config: config).tax
    }

    private var marginalRate: Double {
        TaxEngine.taxForQuotient(data.netAmount, config: config).rate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Summary card
                    VStack(spacing: 12) {
                        HStack {
                            Text("Salaire déclaré")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TaxEngine.cur(data.grossAmount))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        HStack {
                            Text(data.deductionLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("−\(TaxEngine.cur(data.deductionAmount))")
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                        Divider()
                        HStack {
                            Text("Net imposable")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(TaxEngine.cur(data.netAmount))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.blue)
                        }
                    }
                    .font(.callout)
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Bracket breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Barème progressif par tranche", systemImage: "chart.bar.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Simulation pour 1 part fiscale")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        ForEach(Array(brackets.enumerated()), id: \.offset) { _, b in
                            VStack(spacing: 8) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.range)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text("Taux : \(Int(b.rate * 100)) %")
                                            .font(.caption)
                                            .foregroundStyle(.blue)
                                    }
                                    Spacer()
                                    Text(TaxEngine.cur(b.amount))
                                        .font(.callout.weight(.semibold).monospacedDigit())
                                }

                                // Progress bar
                                if totalTax > 0 {
                                    GeometryReader { geo in
                                        let ratio = b.amount / totalTax
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.blue.opacity(0.15))
                                            .frame(height: 6)
                                            .overlay(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 3)
                                                    .fill(b.rate == 0 ? Color.gray.opacity(0.3) : Color.blue)
                                                    .frame(width: max(0, geo.size.width * ratio), height: 6)
                                            }
                                    }
                                    .frame(height: 6)
                                }

                                Divider()
                            }
                        }

                        // Total
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Impôt sur le revenu (1 part)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("TMI : \(Int(marginalRate * 100)) %")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                            Spacer()
                            Text(TaxEngine.cur(totalTax))
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 4)

                        if data.netAmount > 0 {
                            HStack {
                                Text("Taux moyen effectif")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f %%", (totalTax / data.netAmount) * 100))
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    Text("Ce détail montre l'imposition par tranche pour 1 part. L'impôt final dépend du nombre de parts du foyer.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Impôt par tranche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Quotient Familial Detail Sheet

struct QuotientDetailSheet: View {
    let income: Double
    let situation: FamilySituation
    let children: Int
    let result: TaxResult
    let config: TaxConfig
    @Environment(\.dismiss) private var dismiss

    private var baseParts: Double { situation == .couple ? 2.0 : 1.0 }
    private var extraHalfParts: Double { (result.parts - baseParts) * 2 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Explanation
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Qu'est-ce que le quotient familial ?", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text("Le quotient familial divise le revenu imposable par le nombre de parts fiscales du foyer. L'impôt est calculé sur ce quotient, puis multiplié par le nombre de parts. Ce mécanisme avantage les familles nombreuses.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Parts breakdown
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Calcul des parts", systemImage: "person.2.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 8) {
                            partRow(situation == .couple ? "Couple" : situation == .singleParent ? "Parent isolé" : "Célibataire",
                                    value: situation == .couple ? 2.0 : 1.0)

                            if situation == .singleParent {
                                partRow("Majoration parent isolé", value: 0.5)
                            }

                            if children > 0 {
                                let childParts: Double = {
                                    if children <= 2 {
                                        return Double(children) * 0.5
                                    } else {
                                        return 1.0 + Double(children - 2)
                                    }
                                }()

                                if children <= 2 {
                                    partRow("\(children) enfant\(children > 1 ? "s" : "") (× 0,5)", value: childParts)
                                } else {
                                    partRow("2 premiers enfants (× 0,5)", value: 1.0)
                                    partRow("\(children - 2) enfant\(children - 2 > 1 ? "s" : "") supplémentaire\(children - 2 > 1 ? "s" : "") (× 1)", value: Double(children - 2))
                                }
                            }

                            Divider()

                            HStack {
                                Text("Total des parts")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(formatParts(result.parts))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.blue)
                            }
                            .font(.callout)
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Quotient calculation
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Calcul du quotient", systemImage: "function")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Formule :")
                                .font(.subheadline.weight(.semibold))

                            Text("Quotient = Revenu net imposable ÷ Nombre de parts")
                                .font(.callout.monospaced())
                                .foregroundStyle(.blue)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Étape par étape :")
                                .font(.subheadline.weight(.semibold))

                            qStepRow("1", "Revenu net imposable", value: TaxEngine.cur(income))
                            qStepRow("2", "÷ \(formatParts(result.parts)) parts", value: "")
                            qStepRow("3", "\(TaxEngine.cur(income)) ÷ \(formatParts(result.parts))",
                                     value: TaxEngine.cur(result.quotientFamilial))
                        }

                        Divider()

                        HStack {
                            Text("Quotient familial")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(TaxEngine.cur(result.quotientFamilial))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Tax per part then multiplied
                    VStack(alignment: .leading, spacing: 12) {
                        Label("De l'impôt par part à l'impôt brut", systemImage: "multiply.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        let taxPerPart = TaxEngine.taxForQuotient(result.quotientFamilial, config: config).tax

                        HStack {
                            Text("Impôt pour 1 part")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TaxEngine.cur(taxPerPart))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.callout)

                        HStack {
                            Text("× \(formatParts(result.parts)) parts")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .font(.callout)

                        Divider()

                        HStack {
                            Text("Impôt brut")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(TaxEngine.cur(taxPerPart * result.parts))
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(.blue)
                        }

                        // Plafonnement info
                        if result.plafonnement > 0 {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("Plafonnement du quotient familial")
                                        .font(.subheadline.weight(.semibold))
                                }

                                Text("L'avantage procuré par les demi-parts supplémentaires est limité. Le gain d'impôt ne peut pas dépasser \(TaxEngine.cur(config.ceilingPerHalfPart)) par demi-part.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text("Plafonnement appliqué")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("+\(TaxEngine.cur(result.plafonnement))")
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundStyle(.orange)
                                }
                                .font(.callout)

                                HStack {
                                    Text("Impôt brut après plafonnement")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(TaxEngine.cur(result.taxBrut))
                                        .font(.callout.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Advantage
                    if extraHalfParts > 0 {
                        let baseTax = TaxEngine.taxForQuotient(income / baseParts, config: config).tax * baseParts
                        let advantage = baseTax - (TaxEngine.taxForQuotient(result.quotientFamilial, config: config).tax * result.parts)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Économie grâce au quotient familial", systemImage: "arrow.down.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            HStack {
                                Text("Impôt sans enfants / majoration")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TaxEngine.cur(baseTax))
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                            .font(.callout)

                            HStack {
                                Text("Impôt avec \(formatParts(result.parts)) parts")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TaxEngine.cur(TaxEngine.taxForQuotient(result.quotientFamilial, config: config).tax * result.parts))
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                            .font(.callout)

                            Divider()

                            HStack {
                                Text("Économie")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("−\(TaxEngine.cur(max(0, advantage)))")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.green)
                            }

                            if result.plafonnement > 0 {
                                Label("Économie effective après plafonnement : −\(TaxEngine.cur(max(0, advantage - result.plafonnement)))", systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Quotient familial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func partRow(_ label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatParts(value))
                .font(.callout.weight(.semibold).monospacedDigit())
        }
    }

    private func qStepRow(_ step: String, _ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !value.isEmpty {
                    Text(value)
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
            }
            Spacer()
        }
    }

    private func formatParts(_ p: Double) -> String {
        p.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(p))" : String(format: "%.1f", p)
    }
}

// MARK: - Decote Detail Sheet

struct DecoteDetailSheet: View {
    let taxBrut: Double
    let decote: Double
    let isCouple: Bool
    let config: TaxConfig
    @Environment(\.dismiss) private var dismiss

    private var dc: DecoteConfig { config.decote }
    private var threshold: Double { isCouple ? dc.coupleThreshold : dc.singleThreshold }
    private var forfait: Double { isCouple ? dc.coupleForfait : dc.singleForfait }
    private var rawDecote: Double { max(0, forfait - dc.coefficient * taxBrut) }
    private var wasCapped: Bool { rawDecote > taxBrut }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Explanation card
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Qu'est-ce que la décote ?", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)

                        Text("La décote est un mécanisme qui allège l'impôt des contribuables modestes. Elle s'applique lorsque l'impôt brut est inférieur à un certain seuil.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Condition card
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Condition d'éligibilité", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        HStack {
                            Text("Impôt brut")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TaxEngine.cur(taxBrut))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.callout)

                        HStack {
                            Text("Seuil (\(isCouple ? "couple" : "célibataire"))")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(TaxEngine.cur(threshold))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .font(.callout)

                        HStack(spacing: 8) {
                            Image(systemName: taxBrut <= threshold ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(taxBrut <= threshold ? .green : .red)
                            Text(taxBrut <= threshold
                                 ? "\(TaxEngine.cur(taxBrut)) ≤ \(TaxEngine.cur(threshold)) → Décote applicable"
                                 : "\(TaxEngine.cur(taxBrut)) > \(TaxEngine.cur(threshold)) → Pas de décote")
                                .font(.callout.weight(.medium))
                        }
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                    // Calculation card
                    if decote > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Calcul de la décote", systemImage: "function")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            // Formula
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Formule :")
                                    .font(.subheadline.weight(.semibold))

                                Text("Décote = Forfait − (\(String(format: "%.4f", dc.coefficient)) × Impôt brut)")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.blue)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Divider()

                            // Step by step
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Étape par étape :")
                                    .font(.subheadline.weight(.semibold))

                                stepRow("1", "Forfait (\(isCouple ? "couple" : "célibataire"))",
                                        value: TaxEngine.cur(forfait))

                                stepRow("2", "\(String(format: "%.4f", dc.coefficient)) × \(TaxEngine.cur(taxBrut))",
                                        value: TaxEngine.cur(dc.coefficient * taxBrut))

                                stepRow("3", "\(TaxEngine.cur(forfait)) − \(TaxEngine.cur(dc.coefficient * taxBrut))",
                                        value: TaxEngine.cur(rawDecote))

                                if wasCapped {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        Text("La décote est plafonnée au montant de l'impôt brut (\(TaxEngine.cur(taxBrut)))")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }

                            Divider()

                            // Result
                            HStack {
                                Text("Décote appliquée")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("−\(TaxEngine.cur(decote))")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.green)
                            }

                            HStack {
                                Text("Impôt après décote")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TaxEngine.cur(max(0, taxBrut - decote)))
                                    .font(.callout.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding()
                        .background(.background)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    }

                    // Reference
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Paramètres \(config.year)", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Group {
                            paramRow("Seuil célibataire", TaxEngine.cur(dc.singleThreshold))
                            paramRow("Seuil couple", TaxEngine.cur(dc.coupleThreshold))
                            paramRow("Forfait célibataire", TaxEngine.cur(dc.singleForfait))
                            paramRow("Forfait couple", TaxEngine.cur(dc.coupleForfait))
                            paramRow("Coefficient", String(format: "%.4f", dc.coefficient))
                        }

                        Text(config.legalReference)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Décote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func stepRow(_ step: String, _ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(step)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
            }
            Spacer()
        }
    }

    private func paramRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
        }
    }
}

// MARK: - Credit Help Sheet

struct CreditHelpSheet: View {
    let topic: CreditHelpTopic
    let children: Int
    let income: Double
    let config: TaxConfig

    private var emploiCap: Double {
        TaxEngine.emploiDomicileCap(children: children, config: config)
    }

    private var donsAutresCap: Double {
        max(0, income * config.credits.donsAutres.incomePercentCap)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(topic.title)
                            .font(.title3.weight(.bold))
                        Text(topic.taxNature)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Case de déclaration", systemImage: "doc.text")
                            .font(.headline)
                        Text(topic.declarationBox)
                            .font(.title2.weight(.bold).monospaced())
                            .foregroundStyle(.blue)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Comment c'est calculé", systemImage: "function")
                            .font(.headline)

                        switch topic {
                        case .emploiDomicile:
                            Text("Montant retenu = min(dépenses saisies, \(TaxEngine.cur(emploiCap)))")
                            Text("Avantage fiscal = montant retenu × \(Int(config.credits.emploiDomicile.rate * 100)) %")
                            Text("Le plafond est rehaussé selon le nombre d'enfants déclaré dans l'app.")
                        case .donsAide:
                            Text("Montant retenu = min(dons saisis, \(TaxEngine.cur(config.credits.donsAide.cap)))")
                            Text("Réduction = montant retenu × \(Int(config.credits.donsAide.rate * 100)) %")
                            Text("Cette ligne concerne les dons aux organismes venant en aide aux personnes en difficulté.")
                        case .donsAutres:
                            Text("Montant retenu = min(dons saisis, \(TaxEngine.cur(donsAutresCap)))")
                            Text("Réduction = montant retenu × \(Int(config.credits.donsAutres.rate * 100)) %")
                            Text("Le plafond dépend du revenu imposable saisi: \(Int(config.credits.donsAutres.incomePercentCap * 100)) %.")
                        }
                    }
                    .font(.callout)

                    Text("Les cases indiquées sont fournies à titre d'aide. Vérifiez toujours la notice officielle de votre déclaration annuelle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Explication")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Mini Calculator

struct MiniCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var display = "0"
    @State private var accumulator: Double = 0
    @State private var pendingOp: String?
    @State private var resetOnNext = false
    @State private var history: [String] = []

    private let buttons: [[CalcButton]] = [
        [.ac, .plusMinus, .percent, .op("÷")],
        [.digit("7"), .digit("8"), .digit("9"), .op("×")],
        [.digit("4"), .digit("5"), .digit("6"), .op("−")],
        [.digit("1"), .digit("2"), .digit("3"), .op("+")],
        [.digit("0"), .decimal, .backspace, .equals]
    ]

    enum CalcButton: Hashable {
        case digit(String)
        case op(String)
        case decimal
        case equals
        case ac
        case plusMinus
        case percent
        case backspace

        var label: String {
            switch self {
            case .digit(let d): d
            case .op(let o): o
            case .decimal: ","
            case .equals: "="
            case .ac: "AC"
            case .plusMinus: "±"
            case .percent: "%"
            case .backspace: "⌫"
            }
        }

        var backgroundColor: Color {
            switch self {
            case .op, .equals: .blue
            case .ac, .plusMinus, .percent, .backspace: Color(.systemGray4)
            default: Color(.systemGray6)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .op, .equals: .white
            default: .primary
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()

                // History
                if !history.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(history.reversed(), id: \.self) { entry in
                                Text(entry)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 20)
                }

                // Display
                HStack {
                    Spacer()
                    Text(display)
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // Buttons
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { button in
                            Button {
                                tap(button)
                            } label: {
                                Text(button.label)
                                    .font(.title2.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(button.backgroundColor)
                                    .foregroundStyle(button.foregroundColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }

                // Copy button
                Button {
                    UIPasteboard.general.string = display
                        .replacingOccurrences(of: ",", with: ".")
                        .replacingOccurrences(of: "\u{00A0}", with: "")
                        .replacingOccurrences(of: "\u{202F}", with: "")
                        .replacingOccurrences(of: " ", with: "")
                } label: {
                    Label("Copier le résultat", systemImage: "doc.on.doc")
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calculatrice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func tap(_ button: CalcButton) {
        switch button {
        case .digit(let d):
            if resetOnNext || display == "0" {
                display = d
                resetOnNext = false
            } else {
                display += d
            }
        case .decimal:
            if resetOnNext {
                display = "0,"
                resetOnNext = false
            } else if !display.contains(",") {
                display += ","
            }
        case .backspace:
            if display.count > 1 {
                display.removeLast()
            } else {
                display = "0"
            }
        case .ac:
            display = "0"
            accumulator = 0
            pendingOp = nil
            resetOnNext = false
        case .plusMinus:
            if let v = parseDisplay(), v != 0 {
                display = formatResult(-v)
            }
        case .percent:
            if let v = parseDisplay() {
                if pendingOp != nil {
                    // 90 - 10% → 10% of 90 = 9
                    display = formatResult(accumulator * v / 100)
                } else {
                    display = formatResult(v / 100)
                }
            }
        case .op(let op):
            if let pending = pendingOp, let v = parseDisplay() {
                let result = compute(accumulator, pending, v)
                history.append("\(formatResult(accumulator)) \(pending) \(formatResult(v)) = \(formatResult(result))")
                accumulator = result
                display = formatResult(result)
            } else if let v = parseDisplay() {
                accumulator = v
            }
            pendingOp = op
            resetOnNext = true
        case .equals:
            if let pending = pendingOp, let v = parseDisplay() {
                let result = compute(accumulator, pending, v)
                history.append("\(formatResult(accumulator)) \(pending) \(formatResult(v)) = \(formatResult(result))")
                display = formatResult(result)
                accumulator = result
                pendingOp = nil
                resetOnNext = true
            }
        }
    }

    private func parseDisplay() -> Double? {
        Double(display.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func compute(_ a: Double, _ op: String, _ b: Double) -> Double {
        switch op {
        case "+": a + b
        case "−": a - b
        case "×": a * b
        case "÷": b != 0 ? a / b : 0
        default: b
        }
    }

    private func formatResult(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: Int(v)), number: .decimal)
            return formatted.replacingOccurrences(of: ".", with: ",")
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 8
        f.minimumFractionDigits = 0
        f.decimalSeparator = ","
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

#Preview {
    ContentView()
}
