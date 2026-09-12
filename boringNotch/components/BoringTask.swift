import SwiftUI
import Combine

// MARK: - Modèles locaux
struct BoringTask: Identifiable, Codable {
    var id = UUID()
    var title: String
    var done: Bool
}
struct TaskList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var tasks: [BoringTask]
}

// MARK: - Magasin local
final class TaskStore: ObservableObject {
    static let shared = TaskStore()
    @Published var lists: [TaskList] { didSet { save() } }
    private let storageKey = "taskStore.lists"
    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([TaskList].self, from: data) {
            self.lists = decoded
        } else {
            self.lists = [
                TaskList(name: "Perso", tasks: [BoringTask(title: "Faire étude CV", done: false)]),
                TaskList(name: "Projet X", tasks: [BoringTask(title: "Monter le business plan", done: false)])
            ]
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    func addTask(_ title: String, toListAt index: Int) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, lists.indices.contains(index) else { return }
        lists[index].tasks.append(BoringTask(title: t, done: false))
    }
    func toggle(_ task: BoringTask, inListAt index: Int) {
        guard lists.indices.contains(index),
              let i = lists[index].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        lists[index].tasks[i].done.toggle()
    }
    func deleteTask(_ task: BoringTask, inListAt index: Int) {
        guard lists.indices.contains(index) else { return }
        lists[index].tasks.removeAll { $0.id == task.id }
    }
    func updateTask(_ task: BoringTask, newTitle: String, inListAt index: Int) {
        let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, lists.indices.contains(index),
              let i = lists[index].tasks.firstIndex(where: { $0.id == task.id }) else { return }
        lists[index].tasks[i].title = t
    }
    @discardableResult
    func addList(name: String) -> Int { lists.append(TaskList(name: name, tasks: [])); return lists.count - 1 }
    func renameList(at index: Int, to name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, lists.indices.contains(index) else { return }
        lists[index].name = t
    }
    func deleteList(at index: Int) {
        guard lists.indices.contains(index), lists.count > 1 else { return }
        lists.remove(at: index)
    }
}

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
            if tasks.isEmpty {
                errorMessage = "Découpé en \(rows.count) lignes, en-tête \(rows.first?.count ?? 0) colonnes."
            }
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
// MARK: - Parseur CSV robuste
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        // 1) On normalise toutes les fins de ligne en \n
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
// MARK: - Vue
struct TasksView: View {
    @ObservedObject private var store = TaskStore.shared
    @ObservedObject private var feed = SheetFeed.shared
    @AppStorage("selectedTaskListIndex") private var selectedListIndex: Int = 0
    @AppStorage("sheetCSVURL") private var sheetURL: String = ""
    @State private var showingPatron = false
    @State private var newTaskText = ""
    @State private var editingTaskID: UUID?
    @State private var editingText = ""
    @State private var renamingListID: UUID?
    @State private var renameText = ""
    @FocusState private var focus: Field?
    enum Field: Hashable { case task(UUID), list(UUID) }

    private var safeIndex: Int {
        guard !store.lists.isEmpty else { return 0 }
        return min(max(selectedListIndex, 0), store.lists.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            selector
            if showingPatron { patronView } else { addField; localList }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: 200, alignment: .leading)
        .onHover { hovering in
            // Empêche l'encoche de se fermer tant que la souris est sur le panneau (ex. pendant le scroll)
            SharingStateManager.shared.preventNotchClose = hovering
        }
        .onDisappear {
            SharingStateManager.shared.preventNotchClose = false
        }
    }

    private var selector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.lists.enumerated()), id: \.element.id) { index, list in
                    localPill(index: index, list: list)
                }
                Button {
                    let i = store.addList(name: "Nouvelle liste")
                    showingPatron = false; selectedListIndex = i; startRenaming(store.lists[i])
                } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                }.buttonStyle(.plain)
                patronPill
            }
        }
    }

    @ViewBuilder
    private func localPill(index: Int, list: TaskList) -> some View {
        if renamingListID == list.id {
            TextField("Nom", text: $renameText)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(.white).frame(width: 90)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                .focused($focus, equals: .list(list.id)).onSubmit { commitRename(at: index) }
        } else {
            let sel = !showingPatron && index == safeIndex
            Text(list.name)
                .font(.caption).fontWeight(sel ? .semibold : .regular)
                .foregroundStyle(sel ? .white : .gray)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(sel ? Color(nsColor: .secondarySystemFill) : Color.clear))
                .contentShape(Capsule())
                .onTapGesture { showingPatron = false; selectedListIndex = index }
                .contextMenu {
                    Button("Renommer") { startRenaming(list) }
                    Button("Supprimer la liste", role: .destructive) { deleteList(at: index) }
                }
        }
    }

    private var patronPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down.fill").font(.caption2)
            Text("Patron")
        }
        .font(.caption).fontWeight(showingPatron ? .semibold : .regular)
        .foregroundStyle(showingPatron ? .white : .gray)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(showingPatron ? Color.blue.opacity(0.5) : Color.clear))
        .contentShape(Capsule())
        .onTapGesture {
            showingPatron = true
            if feed.tasks.isEmpty { Task { await feed.refresh(from: sheetURL) } }
        }
    }

    private var patronView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sheetURL.isEmpty {
                Text("Colle l'URL CSV du Sheet, puis Entrée :").font(.caption).foregroundStyle(.gray)
                TextField("https://…output=csv", text: $sheetURL)
                    .textFieldStyle(.plain).font(.caption2).foregroundStyle(.white).padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .secondarySystemFill)))
                    .onSubmit { Task { await feed.refresh(from: sheetURL) } }
            } else {
                HStack {
                    Text("\(feed.tasks.count) tâche(s)").font(.caption).foregroundStyle(.gray)
                    Spacer()
                    if feed.isLoading { ProgressView().controlSize(.small) }
                    else {
                        Button { Task { await feed.refresh(from: sheetURL) } } label: {
                            Image(systemName: "arrow.clockwise").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.gray)
                    }
                }
                if let err = feed.errorMessage { Text(err).font(.caption2).foregroundStyle(.orange) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(feed.tasks) { task in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(statusColor(task.status)).frame(width: 7, height: 7).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title).foregroundStyle(.white).font(.callout)
                                    if !task.status.isEmpty {
                                        Text(task.status).font(.caption2).foregroundStyle(.gray)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "en cours": return .orange
        case "a débuter", "à débuter": return .blue
        default: return .gray
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.gray)
            TextField("Ajouter une tâche…", text: $newTaskText)
                .textFieldStyle(.plain).foregroundStyle(.white).font(.callout)
                .onSubmit { store.addTask(newTaskText, toListAt: safeIndex); newTaskText = "" }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .secondarySystemFill)))
    }

    private var localList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.lists[safeIndex].tasks) { task in taskRow(task) }
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: BoringTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? .green : .gray)
                .onTapGesture { store.toggle(task, inListAt: safeIndex) }
            if editingTaskID == task.id {
                TextField("Tâche", text: $editingText)
                    .textFieldStyle(.plain).foregroundStyle(.white).font(.callout)
                    .focused($focus, equals: .task(task.id)).onSubmit { commitEdit(task) }
            } else {
                Text(task.title)
                    .foregroundStyle(task.done ? .gray : .white).strikethrough(task.done).font(.callout)
                    .onTapGesture(count: 2) { startEditing(task) }
                    .contextMenu {
                        Button("Modifier") { startEditing(task) }
                        Button("Supprimer", role: .destructive) { store.deleteTask(task, inListAt: safeIndex) }
                    }
            }
            Spacer()
        }
    }

    private func startEditing(_ task: BoringTask) {
        editingText = task.title; editingTaskID = task.id
        DispatchQueue.main.async { focus = .task(task.id) }
    }
    private func commitEdit(_ task: BoringTask) {
        store.updateTask(task, newTitle: editingText, inListAt: safeIndex); editingTaskID = nil; focus = nil
    }
    private func startRenaming(_ list: TaskList) {
        renameText = list.name; renamingListID = list.id
        DispatchQueue.main.async { focus = .list(list.id) }
    }
    private func commitRename(at index: Int) {
        store.renameList(at: index, to: renameText); renamingListID = nil; focus = nil
    }
    private func deleteList(at index: Int) {
        store.deleteList(at: index)
        if selectedListIndex >= store.lists.count { selectedListIndex = max(store.lists.count - 1, 0) }
    }
}
