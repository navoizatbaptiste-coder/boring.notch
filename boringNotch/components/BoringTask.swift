import SwiftUI
import Combine

// MARK: - Modèles
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

// MARK: - Magasin (sauvegarde automatique sur le disque)
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
                TaskList(name: "Perso", tasks: [
                    BoringTask(title: "Faire étude CV", done: false),
                    BoringTask(title: "Rappeler le notaire", done: false)
                ]),
                TaskList(name: "Projet X", tasks: [
                    BoringTask(title: "Monter le business plan", done: false)
                ]),
                TaskList(name: "Patron", tasks: [
                    BoringTask(title: "Vérifier le bail commercial", done: false)
                ])
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
    func addList(name: String) -> Int {
        lists.append(TaskList(name: name, tasks: []))
        return lists.count - 1
    }

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

// MARK: - Vue
struct TasksView: View {
    @ObservedObject private var store = TaskStore.shared
    @AppStorage("selectedTaskListIndex") private var selectedListIndex: Int = 0
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
            listSelector
            addField
            taskList
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: 180, alignment: .leading)
    }

    private var listSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.lists.enumerated()), id: \.element.id) { index, list in
                    listPill(index: index, list: list)
                }
                Button {
                    let i = store.addList(name: "Nouvelle liste")
                    selectedListIndex = i
                    startRenaming(store.lists[i])
                } label: {
                    Image(systemName: "plus").font(.caption).foregroundStyle(.gray)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func listPill(index: Int, list: TaskList) -> some View {
        if renamingListID == list.id {
            TextField("Nom", text: $renameText)
                .textFieldStyle(.plain).font(.caption).foregroundStyle(.white)
                .frame(width: 90)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                .focused($focus, equals: .list(list.id))
                .onSubmit { commitRename(at: index) }
        } else {
            let isSelected = index == safeIndex
            Text(list.name)
                .font(.caption).fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .gray)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color(nsColor: .secondarySystemFill) : Color.clear))
                .contentShape(Capsule())
                .onTapGesture { selectedListIndex = index }
                .contextMenu {
                    Button("Renommer") { startRenaming(list) }
                    Button("Supprimer la liste", role: .destructive) { deleteList(at: index) }
                }
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

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.lists[safeIndex].tasks) { task in
                    taskRow(task)
                }
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
                    .focused($focus, equals: .task(task.id))
                    .onSubmit { commitEdit(task) }
            } else {
                Text(task.title)
                    .foregroundStyle(task.done ? .gray : .white)
                    .strikethrough(task.done).font(.callout)
                    .onTapGesture(count: 2) { startEditing(task) }
                    .contextMenu {
                        Button("Modifier") { startEditing(task) }
                        Button("Supprimer", role: .destructive) { store.deleteTask(task, inListAt: safeIndex) }
                    }
            }
            Spacer()
        }
    }

    // MARK: Actions
    private func startEditing(_ task: BoringTask) {
        editingText = task.title; editingTaskID = task.id
        DispatchQueue.main.async { focus = .task(task.id) }
    }
    private func commitEdit(_ task: BoringTask) {
        store.updateTask(task, newTitle: editingText, inListAt: safeIndex)
        editingTaskID = nil; focus = nil
    }
    private func startRenaming(_ list: TaskList) {
        renameText = list.name; renamingListID = list.id
        DispatchQueue.main.async { focus = .list(list.id) }
    }
    private func commitRename(at index: Int) {
        store.renameList(at: index, to: renameText)
        renamingListID = nil; focus = nil
    }
    private func deleteList(at index: Int) {
        store.deleteList(at: index)
        if selectedListIndex >= store.lists.count {
            selectedListIndex = max(store.lists.count - 1, 0)
        }
    }
}
