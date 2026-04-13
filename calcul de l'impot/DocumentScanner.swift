//
//  DocumentScanner.swift
//  calcul de l'impot
//
//  Created by Robert Oulhen on 13/04/2026.
//

import SwiftUI
import Vision
import VisionKit
import PhotosUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Extracted Data

struct ExtractedTaxData {
    var revenuBrut: Double?
    var revenuNetImposable: Double?
    var parts: Double?
    var situation: FamilySituation?
    var impotNet: Double?
    var revenuFiscalRef: Double?
    var sourceType: SourceType
    var rawText: String = ""
    var isMonthly: Bool = false
    var parserUsed: String = "regex"

    enum SourceType: String {
        case avisImposition = "Avis d'imposition"
        case attestationFiscale = "Attestation fiscale"
        case bulletinSalaire = "Bulletin de salaire"
        case bulletinPension = "Bulletin de pension"
        case unknown = "Document"
    }
}

// MARK: - AI Tax Parser (OpenAI)

enum AITaxParser {
    static var apiKey: String {
        get { UserDefaults.standard.string(forKey: "openai_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "openai_api_key") }
    }

    static var isAvailable: Bool { !apiKey.isEmpty }

    static func parse(text: String) async -> ExtractedTaxData? {
        guard isAvailable else { return nil }

        let prompt = """
        Analyse ce texte OCR d'un document fiscal français. Retourne un JSON avec ces champs :
        
        - "total_brut": le montant "Total brut" ou "Total +" du document (nombre). Pour bulletin mensuel pension/salaire uniquement.
        - "type": "pension", "salaire", "attestation_fiscale", "avis_imposition" ou "inconnu"
          - "pension" : bulletin MENSUEL de pension (avec détail cotisations, CSG, etc.)
          - "attestation_fiscale" : attestation fiscale ANNUELLE de pension ou salaire (donne le "montant imposable de l'année" directement)
          - "salaire" : bulletin de salaire mensuel
          - "avis_imposition" : avis d'imposition des impôts
        - "is_monthly": true si bulletin mensuel, false si annuel ou attestation fiscale
        - "montant_imposable": (attestation_fiscale uniquement) le "montant imposable de l'année" — c'est le montant ANNUEL à déclarer, déjà net de CSG.
        - "revenu_net_imposable": (avis d'imposition uniquement) le "revenu net imposable" ou "revenu imposable". ATTENTION : c'est un REVENU (généralement plusieurs milliers d'euros), à ne PAS confondre avec le montant de l'impôt.
        - "revenu_brut_global": (avis d'imposition uniquement) le "revenu brut global" ou "total des revenus et gains nets"
        - "situation": "couple" ou "celibataire" ou null
        - "parts": nombre de parts fiscales ou null
        - "impot_net": le montant de l'IMPÔT (intitulé "impôt sur le revenu net", "montant de votre impôt", "prélevé à la source", etc.). C'est un montant beaucoup plus petit que le revenu. Ne pas confondre avec le revenu net imposable.
        
        Réponds UNIQUEMENT avec le JSON.
        
        Texte OCR:
        \(text.prefix(4000))
        """

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return nil }
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
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }

        // Parse the JSON response
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let resultData = cleaned.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] else { return nil }

        let type: ExtractedTaxData.SourceType
        switch (result["type"] as? String ?? "") {
        case "pension": type = .bulletinPension
        case "salaire": type = .bulletinSalaire
        case "attestation_fiscale": type = .attestationFiscale
        case "avis_imposition": type = .avisImposition
        default: type = .unknown
        }

        let isMonthly = result["is_monthly"] as? Bool ?? false
        let multiplier: Double = isMonthly ? 12 : 1

        var situation: FamilySituation?
        if let s = result["situation"] as? String {
            if s.contains("couple") || s.contains("mari") || s.contains("pacs") { situation = .couple }
            else if s.contains("celib") { situation = .single }
        }

        var extracted = ExtractedTaxData(sourceType: type, rawText: text, isMonthly: isMonthly, parserUsed: "AI")

        if type == .avisImposition {
            if let v = result["revenu_net_imposable"] as? Double { extracted.revenuNetImposable = v * multiplier }
            if let v = result["revenu_brut_global"] as? Double { extracted.revenuBrut = v * multiplier }
        } else if type == .attestationFiscale {
            // Attestation fiscale annuelle: montant imposable already net of CSG
            if let v = result["montant_imposable"] as? Double { extracted.revenuBrut = v }
        } else {
            // Monthly pension/salary bulletin: total_brut includes CSG → subtract it
            if let brut = result["total_brut"] as? Double {
                let montantImposable = brut * (1 - 0.059)  // CSG déductible = 5.9%
                extracted.revenuBrut = montantImposable * multiplier
            }
        }

        extracted.situation = situation
        extracted.parts = result["parts"] as? Double
        if let v = result["impot_net"] as? Double { extracted.impotNet = v }

        return extracted
    }
}

// MARK: - OCR Parser

enum TaxDocumentParser {

    static func parse(text: String) -> ExtractedTaxData {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let fullText = lines.joined(separator: "\n").lowercased()

        // Detect source type — check most specific first
        let sourceType: ExtractedTaxData.SourceType
        if (fullText.contains("montant imposable") && fullText.contains("l'année") || fullText.contains("de l\u{2019}année"))
            && (fullText.contains("déclaration préremplie") || fullText.contains("declaration preremplie")
                || fullText.contains("attestation fiscale") || fullText.contains("vous devez déclarer")
                || fullText.contains("vous devez declarer")
                || fullText.contains("montant imposable de l'année") || fullText.contains("montant imposable de l\u{2019}année")) {
            sourceType = .attestationFiscale
        } else if fullText.contains("bulletin de pension")
            || (fullText.contains("pension") && fullText.contains("retraite"))
            || fullText.contains("retraitesdeletat")
            || fullText.contains("pension principale")
            || fullText.contains("pension militaire") {
            sourceType = .bulletinPension
        } else if fullText.contains("bulletin de paie") || fullText.contains("bulletin de salaire")
                    || (fullText.contains("net à payer") && fullText.contains("salaire de base")) {
            sourceType = .bulletinSalaire
        } else if fullText.contains("avis d") && fullText.contains("imposition") || fullText.contains("revenu fiscal")
                    || fullText.contains("dgfip") || fullText.contains("impots.gouv") || fullText.contains("impôts.gouv") {
            sourceType = .avisImposition
        } else {
            sourceType = .unknown
        }

        var data = ExtractedTaxData(sourceType: sourceType, rawText: text)

        // --- Attestation fiscale annuelle: montant imposable used directly ---
        if sourceType == .attestationFiscale {
            for line in lines {
                let lower = line.lowercased()
                if lower.contains("montant imposable") || lower.contains("vous devez déclarer") || lower.contains("vous devez declarer") {
                    if let amount = extractMonetaryAmount(from: line) ?? extractAmount(from: line) {
                        data.revenuBrut = amount
                        break
                    }
                }
            }
            // Fallback: find the largest monetary amount
            if data.revenuBrut == nil {
                var fallbackMax: Double = 0
                for line in lines {
                    if let a = extractMonetaryAmount(from: line), a > fallbackMax { fallbackMax = a }
                }
                if fallbackMax > 0 { data.revenuBrut = fallbackMax }
            }
        }

        // --- Pension/salary bulletin: montant imposable = Total brut − CSG déductible ---
        // Collect all monetary amounts, find total brut (highest with centimes)
        // and CSG déductible (amount on/near the CSG deductible label line).
        if sourceType == .bulletinPension || sourceType == .bulletinSalaire {
            var allMonetary: [Double] = []
            var csgDeductible: Double?
            for (i, line) in lines.enumerated() {
                let lower = line.lowercased()
                // Collect all unique monetary amounts
                if let amount = extractMonetaryAmount(from: line), amount > 1 {
                    if !allMonetary.contains(where: { abs($0 - amount) < 0.01 }) {
                        allMonetary.append(amount)
                    }
                }
                // Find CSG déductible amount
                if csgDeductible == nil &&
                    (lower.contains("c.s.g. deductible") || lower.contains("csg déductible") || lower.contains("csg deductible")) {
                    // Amount might be on same line or next lines
                    csgDeductible = extractMonetaryAmount(from: line)
                    if csgDeductible == nil {
                        for j in (i + 1)..<min(i + 4, lines.count) {
                            if let a = extractMonetaryAmount(from: lines[j]) {
                                csgDeductible = a
                                break
                            }
                        }
                    }
                }
            }
            // Total brut = highest monetary amount in the document
            if let maxAmount = allMonetary.max() {
                // Always deduct CSG: use found value, or apply 5.9% rate
                let csg = csgDeductible ?? (maxAmount * 0.059)
                data.revenuBrut = maxAmount - csg
            }
        }

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            let contextLines = (1...3).compactMap { i + $0 < lines.count ? lines[i + $0] : nil }
            let context1 = contextLines.first ?? ""

            // --- Revenu net imposable (avis d'imposition) ---
            if data.revenuNetImposable == nil &&
                (lower.contains("revenu net imposable") || lower.contains("net imposable") ||
                 lower.contains("revenu imposable")) {
                data.revenuNetImposable = extractAmount(from: line)
                    ?? extractAmountFromContext(contextLines)
            }

            // --- Revenu brut global (avis d'imposition) ---
            if data.revenuBrut == nil &&
                (lower.contains("revenu brut global") || lower.contains("total des revenus") ||
                 lower.contains("traitements et salaires") || lower.contains("salaire brut")) {
                data.revenuBrut = extractAmount(from: line)
                    ?? extractAmountFromContext(contextLines)
            }

            // --- Revenu fiscal de référence ---
            if data.revenuFiscalRef == nil && lower.contains("revenu fiscal de référence") {
                data.revenuFiscalRef = extractAmount(from: line)
                    ?? extractAmountFromContext(contextLines)
            }

            // --- Cumul net imposable (bulletin salaire annuel) ---
            if lower.contains("cumul") && lower.contains("net imposable") {
                data.revenuNetImposable = extractAmount(from: line)
                    ?? extractAmountFromContext(contextLines)
            }

            // --- Nombre de parts ---
            if lower.contains("nombre de part") || lower.contains("nb de parts") || lower.contains("parts fiscales") {
                data.parts = extractDecimal(from: line) ?? extractDecimal(from: context1)
            }

            // --- Impôt net ---
            if data.impotNet == nil &&
                (lower.contains("impôt net") || lower.contains("impot net") ||
                 lower.contains("montant de votre impôt") || lower.contains("montant de l'impôt") ||
                 lower.contains("impôt sur le revenu net")) &&
                !lower.contains("avant") && !lower.contains("prélevé") && !lower.contains("source") {
                data.impotNet = extractAmount(from: line)
                    ?? extractAmountFromContext(contextLines)
            }

            // --- Situation familiale ---
            if data.situation == nil &&
                (lower.contains("situation de famille") || lower.contains("situation familiale") ||
                 lower.contains("état civil")) {
                let combined = ([lower] + contextLines.map { $0.lowercased() }).joined(separator: " ")
                if combined.contains("marié") || combined.contains("marie") || combined.contains("pacsé") || combined.contains("pacse") {
                    data.situation = .couple
                } else if combined.contains("célibataire") || combined.contains("celibataire") || combined.contains("divorcé") || combined.contains("divorce") {
                    data.situation = .single
                } else if combined.contains("veuf") || combined.contains("veuve") {
                    data.situation = .single
                }
            }
        }

        // Fallback: use revenu fiscal de référence as net imposable
        if data.revenuNetImposable == nil, let rfr = data.revenuFiscalRef {
            data.revenuNetImposable = rfr
        }

        // Infer situation from parts if not found
        if data.situation == nil, let parts = data.parts {
            if parts >= 2.0 { data.situation = .couple }
        }

        // Annualize monthly bulletins (pension or salary)
        if sourceType == .bulletinPension || sourceType == .bulletinSalaire {
            let hasAnnualKeyword = fullText.contains("cumul annuel") || fullText.contains("annuel")
            if !hasAnnualKeyword {
                data.isMonthly = true
                if let v = data.revenuBrut { data.revenuBrut = v * 12 }
                if let v = data.revenuNetImposable { data.revenuNetImposable = v * 12 }
            }
        }

        return data
    }

    private static func extractAmountFromContext(_ lines: [String]) -> Double? {
        for line in lines {
            if let amount = extractAmount(from: line) {
                return amount
            }
        }
        return nil
    }

    /// Only matches amounts WITH centimes (e.g. 1 444,38 or 1312,94) — excludes years, postal codes, etc.
    /// Returns the LARGEST matching amount from the text to avoid partial matches (444,38 instead of 1 444,38).
    private static func extractMonetaryAmount(from text: String) -> Double? {
        let patterns = [
            #"(\d{1,3}(?:[\s\u{00A0}]\d{3})+[,\.]\d{2})"#,  // 1 444,38
            #"(\d+[,\.]\d{2})"#,                                // 1444,38 or 131,44
            #"(\d{1,3}(?:\.\d{3})+,\d{2})"#                    // 1.444,38
        ]
        var best: Double?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let matchRange = Range(match.range(at: 1), in: text) else { continue }
                var numStr = String(text[matchRange])
                numStr = numStr.replacingOccurrences(of: "\u{00A0}", with: "")
                numStr = numStr.replacingOccurrences(of: " ", with: "")
                if numStr.contains(",") && !numStr.contains(".") {
                    numStr = numStr.replacingOccurrences(of: ",", with: ".")
                } else if numStr.contains(".") && numStr.contains(",") {
                    numStr = numStr.replacingOccurrences(of: ".", with: "")
                    numStr = numStr.replacingOccurrences(of: ",", with: ".")
                }
                if let val = Double(numStr), val > 0 {
                    if best == nil || val > best! { best = val }
                }
            }
        }
        return best
    }

    private static func extractAmount(from text: String) -> Double? {
        // Match patterns like: 35 000, 35000, 35 000,00, 35000.00, 35.000,00
        let patterns = [
            #"(\d{1,3}(?:[\s\u{00A0}]\d{3})+(?:[,\.]\d{2})?)"#,  // 35 000 or 35 000,00
            #"(\d{4,}(?:[,\.]\d{2})?)"#,                            // 35000 or 35000.00
            #"(\d{1,3}(?:\.\d{3})+(?:,\d{2})?)"#                   // 35.000,00
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)

            // Take the last match (amount is usually at the end of the line)
            if let match = matches.last,
               let matchRange = Range(match.range(at: 1), in: text) {
                var numStr = String(text[matchRange])
                numStr = numStr.replacingOccurrences(of: "\u{00A0}", with: "")
                numStr = numStr.replacingOccurrences(of: " ", with: "")

                // Handle French decimal format (35000,50)
                if numStr.contains(",") && !numStr.contains(".") {
                    // If ends with ,XX it's a decimal
                    if numStr.hasSuffix(String(numStr.suffix(3))) && numStr.suffix(3).first == "," {
                        numStr = numStr.replacingOccurrences(of: ",", with: ".")
                    } else {
                        numStr = numStr.replacingOccurrences(of: ",", with: "")
                    }
                } else if numStr.contains(".") && numStr.contains(",") {
                    // 35.000,00 format
                    numStr = numStr.replacingOccurrences(of: ".", with: "")
                    numStr = numStr.replacingOccurrences(of: ",", with: ".")
                }

                if let val = Double(numStr), val > 0 {
                    return val
                }
            }
        }
        return nil
    }

    private static func extractDecimal(from text: String) -> Double? {
        let pattern = #"(\d+[,\.]\d+|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.matches(in: text, range: range).last,
           let matchRange = Range(match.range(at: 1), in: text) {
            let numStr = String(text[matchRange]).replacingOccurrences(of: ",", with: ".")
            return Double(numStr)
        }
        return nil
    }
}

// MARK: - OCR Engine

enum OCREngine {
    static func recognizeText(from image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }

        let cgImg = cgImage // local copy for Sendable
        return await Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, _ in
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["fr-FR", "en-US"]
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }.value
    }

    @MainActor
    static func renderPDFPage(document: PDFDocument, index: Int) -> UIImage? {
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    /// Renders PDF pages on main thread, runs OCR on each in background, returns combined text.
    @MainActor
    static func ocrPDF(url: URL) async -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var allText = ""
        for i in 0..<document.pageCount {
            guard let image = renderPDFPage(document: document, index: i) else { continue }
            let pageText = await recognizeText(from: image)
            allText += pageText + "\n"
        }
        return allText
    }
}

// MARK: - Document Camera

struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: ([Data]) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // Copy image data immediately while scan object is still valid
            var imageDataArray: [Data] = []
            for i in 0..<scan.pageCount {
                if let data = scan.imageOfPage(at: i).jpegData(compressionQuality: 0.95) {
                    imageDataArray.append(data)
                }
            }
            parent.onScan(imageDataArray)
            parent.onDismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onDismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onDismiss()
        }
    }
}

// MARK: - Scan Result View

struct ScanResultView: View {
    let data: ExtractedTaxData
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showRawText = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        Text(data.sourceType.rawValue)
                            .font(.headline)
                    }

                    VStack(spacing: 12) {
                        if let v = data.revenuNetImposable {
                            extractedRow("Revenu net imposable", value: TaxEngine.cur(v))
                        }
                        if let v = data.revenuBrut {
                            extractedRow("Revenu brut", value: TaxEngine.cur(v))
                        }
                        if let v = data.revenuFiscalRef {
                            extractedRow("Revenu fiscal de réf.", value: TaxEngine.cur(v))
                        }
                        if let s = data.situation {
                            extractedRow("Situation", value: s.rawValue)
                        }
                        if let p = data.parts {
                            extractedRow("Parts", value: String(format: "%.1f", p))
                        }
                        if let v = data.impotNet {
                            extractedRow("Impôt net", value: TaxEngine.cur(v))
                        }

                        if data.isMonthly {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Montants mensuels annualisés (× 12)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: data.parserUsed == "AI" ? "brain" : "text.magnifyingglass")
                                .foregroundStyle(data.parserUsed == "AI" ? .purple : .orange)
                            Text("Parser: \(data.parserUsed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if data.revenuNetImposable == nil && data.revenuBrut == nil {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Aucun montant détecté.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if data.revenuNetImposable != nil || data.revenuBrut != nil {
                        Button {
                            onUse()
                            dismiss()
                        } label: {
                            Label("Utiliser ces valeurs", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                                )
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    Button { dismiss() } label: {
                        Text("Annuler")
                            .foregroundStyle(.secondary)
                    }

                    // Debug: raw OCR text
                    Button {
                        showRawText.toggle()
                    } label: {
                        Label(showRawText ? "Masquer le texte brut" : "Voir le texte brut (debug)",
                              systemImage: showRawText ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showRawText {
                        Text(data.rawText.isEmpty ? "(aucun texte détecté)" : data.rawText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Résultat du scan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func extractedRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.callout)
    }
}
