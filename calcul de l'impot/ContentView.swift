//
//  ContentView.swift
//  calcul de l'impot
//
//  Created by Robert Oulhen on 12/04/2026.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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

    private static func taxForQuotient(_ q: Double, config: TaxConfig) -> (tax: Double, rate: Double, details: [TaxBracketDetail]) {
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

// MARK: - View

struct ContentView: View {
    @State private var configLoader = TaxConfigLoader()
    @State private var incomeText1 = ""
    @State private var incomeText2 = ""
    @State private var isGrossSalary = true
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

    private var config: TaxConfig { configLoader.config }

    @FocusState private var focusedField: Field?

    enum Field: Hashable { case income1, income2, emploi, donsAide, donsAutres }

    private func parseAmount(_ text: String) -> Double {
        Double(text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private func netImposable(_ gross: Double) -> Double {
        guard isGrossSalary else { return gross }
        return TaxEngine.netImposable(gross, config: config)
    }

    private var income: Double {
        let a = netImposable(parseAmount(incomeText1))
        let b = situation == .couple ? netImposable(parseAmount(incomeText2)) : 0
        return a + b
    }

    private var abattementTotal: Double {
        let g1 = parseAmount(incomeText1)
        let g2 = situation == .couple ? parseAmount(incomeText2) : 0
        let n1 = netImposable(g1)
        let n2 = netImposable(g2)
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
                    calculateButton
                    if let result { resultCards(result) }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Impôt \(config.year)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
        if let net = data.revenuNetImposable {
            isGrossSalary = false
            if declarant == 2 {
                incomeText2 = String(Int(net))
            } else {
                incomeText1 = String(Int(net))
            }
        } else if let brut = data.revenuBrut {
            isGrossSalary = true
            if declarant == 2 {
                incomeText2 = String(Int(brut))
            } else {
                incomeText1 = String(Int(brut))
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

            // Income type toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Type de revenu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $isGrossSalary) {
                    Text("Salaire brut fiscal").tag(true)
                    Text("Net imposable").tag(false)
                }
                .pickerStyle(.segmented)
                if isGrossSalary {
                    let d = config.deduction
                    Label("Abattement de \(Int(d.rate * 100)) % appliqué automatiquement (min \(TaxEngine.cur(d.min)), max \(TaxEngine.cur(d.max)))", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }

            // Income
            VStack(alignment: .leading, spacing: 6) {
                Text(situation == .couple
                     ? (isGrossSalary ? "Salaire brut fiscal — Déclarant 1" : "Revenu net imposable — Déclarant 1")
                     : (isGrossSalary ? "Salaire brut fiscal annuel" : "Revenu net imposable annuel"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $incomeText1, field: .income1)
            }

            if situation == .couple {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isGrossSalary ? "Salaire brut fiscal — Déclarant 2" : "Revenu net imposable — Déclarant 2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    incomeField(text: $incomeText2, field: .income2)
                }
            }

            // Summary after deduction
            if income > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if isGrossSalary && abattementTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Abattement 10 % : −\(TaxEngine.cur(abattementTotal))")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Revenu net imposable : \(TaxEngine.cur(income))")
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
                Label("Crédit de \(Int(config.credits.emploiDomicile.rate * 100)) % — Plafond \(TaxEngine.cur(TaxEngine.emploiDomicileCap(children: children, config: config)))", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dons — aide aux personnes en difficulté")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $donsAideText, field: .donsAide)
                Label("Réduction de \(Int(config.credits.donsAide.rate * 100)) % — Plafond \(TaxEngine.cur(config.credits.donsAide.cap))", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dons — autres organismes d'intérêt général")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                incomeField(text: $donsAutresText, field: .donsAutres)
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

    // MARK: - Calculate Button

    private var calculateButton: some View {
        Button {
            focusedField = nil
            guard income > 0 else { return }
            withAnimation(.spring(duration: 0.4)) {
                result = TaxEngine.calculate(
                    income: income,
                    situation: situation,
                    children: children,
                    emploiDomicile: parseAmount(emploiDomicileText),
                    donsAide: parseAmount(donsAideText),
                    donsAutres: parseAmount(donsAutresText),
                    config: config
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
                Text("Impôt à payer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(TaxEngine.cur(r.taxAfterCredits))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                if r.taxAfterCredits > 0 {
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
                metric("Quotient", value: TaxEngine.cur(r.quotientFamilial), icon: "divide.circle")
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
                row("Décote", value: r.decote, color: .green, prefix: "−")
            }

            row("Impôt après décote", value: r.taxNet)

            if r.creditEmploiDomicile > 0 {
                row("Crédit emploi à domicile (\(Int(config.credits.emploiDomicile.rate * 100)) %)", value: r.creditEmploiDomicile, color: .green, prefix: "−")
            }

            if r.creditDonsAide > 0 {
                row("Réduction dons aide (\(Int(config.credits.donsAide.rate * 100)) %)", value: r.creditDonsAide, color: .green, prefix: "−")
            }

            if r.creditDonsAutres > 0 {
                row("Réduction dons organismes (\(Int(config.credits.donsAutres.rate * 100)) %)", value: r.creditDonsAutres, color: .green, prefix: "−")
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

    // MARK: - Helpers

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

#Preview {
    ContentView()
}
