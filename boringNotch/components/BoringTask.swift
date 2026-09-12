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
