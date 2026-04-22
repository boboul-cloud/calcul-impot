//
//  CasesDeclaration.swift
//  calcul de l'impot
//
//  Loader and viewer for the official 2042 declaration boxes.
//  Data extracted from the open-source OpenFisca-France project.
//

import SwiftUI

// MARK: - Model

struct CaseDeclaration: Codable, Identifiable, Hashable {
    let `case`: String
    let variable: String
    let libelle: String
    let reference: String?

    var id: String { "\(`case`)|\(variable)" }
}

// MARK: - Store

@MainActor @Observable
final class CasesDeclarationStore {
    private(set) var all: [CaseDeclaration] = []
    private(set) var loadError: String?

    func loadIfNeeded() {
        guard all.isEmpty, loadError == nil else { return }
        guard let url = Bundle.main.url(forResource: "cases_2042", withExtension: "json") else {
            loadError = "Fichier cases_2042.json introuvable dans le bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            all = try JSONDecoder().decode([CaseDeclaration].self, from: data)
        } catch {
            loadError = "Erreur de chargement : \(error.localizedDescription)"
        }
    }

    /// Returns the first case matching the given Cerfa code (e.g. "1AJ", "7DB").
    func first(matching code: String) -> CaseDeclaration? {
        let needle = code.uppercased()
        return all.first { $0.case.uppercased() == needle }
    }
}

// MARK: - Browser View

struct CasesDeclarationView: View {
    @State private var store = CasesDeclarationStore()
    @State private var search: String = ""
    @State private var selectedSection: String = "Toutes"
    @Environment(\.dismiss) private var dismiss

    private var sections: [String] {
        // Section is the first character of the case code (1, 2, 3, …, 7, 8)
        let unique = Set(store.all.map { String($0.case.prefix(1)) })
        return ["Toutes"] + unique.sorted()
    }

    private var filtered: [CaseDeclaration] {
        let bySection: [CaseDeclaration]
        if selectedSection == "Toutes" {
            bySection = store.all
        } else {
            bySection = store.all.filter { $0.case.hasPrefix(selectedSection) }
        }
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return bySection }
        let needle = trimmed.lowercased()
        return bySection.filter {
            $0.case.lowercased().contains(needle)
                || $0.libelle.lowercased().contains(needle)
        }
    }

    private static let sectionLabels: [String: String] = [
        "1": "1 — Traitements, salaires, pensions",
        "2": "2 — Revenus de capitaux mobiliers",
        "3": "3 — Plus-values et gains divers",
        "4": "4 — Revenus fonciers",
        "5": "5 — Revenus non salariaux",
        "6": "6 — Charges déductibles",
        "7": "7 — Réductions et crédits d'impôt",
        "8": "8 — Divers"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let err = store.loadError {
                    ContentUnavailableView(
                        "Erreur",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else if store.all.isEmpty {
                    ProgressView("Chargement des cases…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Picker("Section", selection: $selectedSection) {
                                ForEach(sections, id: \.self) { s in
                                    Text(Self.sectionLabels[s] ?? s).tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Section {
                            ForEach(filtered) { item in
                                NavigationLink(value: item) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(item.case)
                                            .font(.callout.monospaced().weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.12))
                                            .foregroundStyle(.blue)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(item.libelle)
                                            .font(.subheadline)
                                            .lineLimit(3)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Text("\(filtered.count) case\(filtered.count > 1 ? "s" : "")")
                        } footer: {
                            Text("Source : OpenFisca-France (open data, sous licence libre). Les libellés et codes correspondent au formulaire 2042 publié par la DGFiP.")
                                .font(.caption2)
                        }
                    }
                    .navigationDestination(for: CaseDeclaration.self) { item in
                        CaseDetailView(item: item)
                    }
                }
            }
            .searchable(text: $search, prompt: "Rechercher (ex. 1AJ, salaire, dons…)")
            .navigationTitle("Cases déclaration 2042")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { store.loadIfNeeded() }
        }
    }
}

// MARK: - Detail View

struct CaseDetailView: View {
    let item: CaseDeclaration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Text(item.case)
                        .font(.largeTitle.monospaced().weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Intitulé officiel")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.libelle)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Variable OpenFisca")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.variable)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }

                if let ref = item.reference, !ref.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Référence légale")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let url = URL(string: ref), ref.lowercased().hasPrefix("http") {
                            Link(ref, destination: url)
                                .font(.callout)
                        } else {
                            Text(ref)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }

                Link(destination: URL(string: "https://www.impots.gouv.fr/formulaire/2042/declaration-des-revenus")!) {
                    Label("Ouvrir le formulaire 2042 officiel", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
        .navigationTitle("Case \(item.case)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Compact help button

/// A small button to display next to a form field, showing the official
/// Cerfa box code. Tapping opens a sheet with the full description.
struct CaseHelpBadge: View {
    let code: String
    @State private var showDetail = false
    @State private var store = CasesDeclarationStore()

    var body: some View {
        Button {
            store.loadIfNeeded()
            showDetail = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text("Case \(code)")
                    .font(.caption2.monospaced().weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.10))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voir la définition de la case \(code)")
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                if let item = store.first(matching: code) {
                    CaseDetailView(item: item)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fermer") { showDetail = false }
                            }
                        }
                } else {
                    ContentUnavailableView(
                        "Case \(code) introuvable",
                        systemImage: "questionmark.circle",
                        description: Text("Cette case n'est pas répertoriée dans la base OpenFisca embarquée.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { showDetail = false }
                        }
                    }
                }
            }
        }
    }
}
