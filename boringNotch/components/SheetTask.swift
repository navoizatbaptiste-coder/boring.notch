//
//  SheetTask.swift
//  boringNotch
//
//  Created by Baptiste Navoizat on 12/09/2026.
//


import SwiftUI
import Combine

// MARK: - Tâche venant du Sheet du patron
struct SheetTask: Identifiable {
    let id: String
    let title: String
    let status: String
    let persons: String
}

// MARK: - Lecteur du Google Sheet publié en CSV
@MainActor
final class SheetFeed: ObservableObject {
    static let shared = SheetFeed()
    @Published var tasks: [SheetTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let me = "baptiste"

    func refresh(from urlString: String) async {
        let s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s) else {
            errorMessage = "Ajoute l'URL du Sheet."; return
        }
        isLoading = true; errorMessage = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let csv = String(decoding: data, as: UTF8.self)
            let rows = CSVParser.parse(csv)
            tasks = Self.build(from: rows, me: me)
            if tasks.isEmpty { errorMessage = "Aucune tâche ouverte pour toi." }
        } catch {
            errorMessage = "Échec du chargement."
        }
        isLoading = false
    }

    private static func build(from rows: [[String]], me: String) -> [SheetTask] {
        guard rows.count > 1 else { return [] }
        var out: [SheetTask] = []
        for row in rows.dropFirst() {
            guard row.count >= 5 else { continue }
            let id = row[0].trimmingCharacters(in: .whitespaces)
            let persons = row[2]
            let title = row[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let status = row[4].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !title.isEmpty else { continue }
            guard persons.lowercased().contains(me) else { continue }
            if status.lowercased() == "achevé" { continue }
            out.append(SheetTask(id: id, title: title, status: status, persons: persons))
        }
        return out
    }
}

// MARK: - Parseur CSV robuste
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        for c in normalized {
            if inQuotes {
                if c == "\"" { inQuotes = false }
                else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": record.append(field); field = ""
                case "\n": record.append(field); field = ""; rows.append(record); record = []
                default: field.append(c)
                }
            }
        }
        record.append(field)
        if record.count > 1 || !(record.first?.isEmpty ?? true) { rows.append(record) }
        return rows
    }
}