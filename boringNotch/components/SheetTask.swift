import SwiftUI
import Combine
import UserNotifications

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

    // IDs déjà connus, pour détecter les nouveautés
    private var knownIDs: Set<String> = []
    private var hasLoadedOnce = false
    // Appelé quand de nouvelles tâches arrivent (nouveaux IDs)
    var onNewTasks: (([SheetTask]) -> Void)?

    private let me = "baptiste"
    private var timer: Timer?

    // Démarre le rafraîchissement automatique (toutes les 10 min)
    func startAutoRefresh(url: String) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { await self?.refresh(from: url) }
        }
        Task { await refresh(from: url) }  // un premier chargement immédiat
    }

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
            let newList = Self.build(from: rows, me: me)
            detectNew(newList)
            tasks = newList
            if tasks.isEmpty { errorMessage = "Aucune tâche ouverte pour toi." }
        } catch {
            errorMessage = "Échec du chargement."
        }
        isLoading = false
    }

    private func detectNew(_ incoming: [SheetTask]) {
        let incomingIDs = Set(incoming.map { $0.id })
        if !hasLoadedOnce {
            // Premier chargement : on mémorise l'état sans déclencher de pop-up
            knownIDs = incomingIDs
            hasLoadedOnce = true
            return
        }
        let newOnes = incoming.filter { !knownIDs.contains($0.id) }
        knownIDs.formUnion(incomingIDs)
        if !newOnes.isEmpty {
            onNewTasks?(newOnes)
        }
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
// MARK: - Notifications système
// MARK: - Notifications système
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(_ tasks: [SheetTask]) {
        let content = UNMutableNotificationContent()
        if tasks.count == 1 {
            content.title = "Nouvelle tâche du patron"
            content.body = tasks[0].title
        } else {
            content.title = "\(tasks.count) nouvelles tâches du patron"
            content.body = tasks.prefix(3).map { $0.title }.joined(separator: " • ")
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Autorise l'affichage même quand l'app est au premier plan
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
