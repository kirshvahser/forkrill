import Foundation
import SwiftData
import Network
import Security

// MARK: - Источник данных
// Сейчас MockProvider. Когда найдём API Modeus, пишем ModeusProvider и подставляем сюда.

struct LessonDTO: Codable {
    let id: String
    let title: String
    let room: String
    let teacher: String
    let start: Date
    let end: Date
}

protocol ScheduleProvider {
    func fetchLessons() async throws -> [LessonDTO]
}

struct MockProvider: ScheduleProvider {
    func fetchLessons() async throws -> [LessonDTO] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: .now)
        func t(_ h: Int) -> Date { cal.date(byAdding: .hour, value: h, to: day)! }
        return [
            LessonDTO(id: "1", title: "Алгоритмы", room: "305", teacher: "Иванов", start: t(10), end: t(11)),
            LessonDTO(id: "2", title: "Базы данных", room: "112", teacher: "Петрова", start: t(12), end: t(13)),
            LessonDTO(id: "3", title: "Сети", room: "208", teacher: "Сидоров", start: t(14), end: t(15))
        ]
    }
}

// MARK: - Синк: появилась сеть -> обновили кэш; старше 2 месяцев -> удалили

@MainActor
final class SyncService: ObservableObject {
    static let retention: TimeInterval = 60 * 24 * 3600   // 60 дней

    @Published var lastSync: Date?
    @Published var isOnline = false

    var provider: ScheduleProvider = MockProvider()
    private let monitor = NWPathMonitor()

    func start(context: ModelContext) {
        purge(context)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                if self.isOnline { await self.sync(context) }
            }
        }
        monitor.start(queue: .global())
    }

    func sync(_ context: ModelContext) async {
        do {
            let items = try await provider.fetchLessons()
            for d in items {
                let id = d.id
                let found = try context.fetch(
                    FetchDescriptor<Lesson>(predicate: #Predicate { $0.id == id })
                ).first
                if let l = found {
                    l.title = d.title; l.room = d.room; l.teacher = d.teacher
                    l.start = d.start; l.end = d.end; l.syncedAt = .now
                } else {
                    context.insert(Lesson(id: d.id, title: d.title, room: d.room,
                                          teacher: d.teacher, start: d.start, end: d.end))
                }
            }
            try context.save()
            lastSync = .now
        } catch {
            print("Sync failed:", error)   // офлайн или ошибка: просто остаёмся на кэше
        }
    }

    func purge(_ context: ModelContext) {
        let limit = Date.now.addingTimeInterval(-Self.retention)
        try? context.delete(model: Lesson.self, where: #Predicate { $0.syncedAt < limit })
    }
}

// MARK: - Keychain: храним токен сессии, а не пароль

enum Keychain {
    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
