import SwiftUI
import SwiftData

@main
struct StudyApp: App {
    @StateObject private var sync = SyncService()

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(sync)
        }
        .modelContainer(for: [Lesson.self, Cheat.self])
    }
}

// MARK: - Модели (хранятся локально, работают офлайн)

@Model final class Lesson {
    @Attribute(.unique) var id: String
    var title: String
    var room: String
    var teacher: String
    var start: Date
    var end: Date
    var syncedAt: Date   // когда последний раз обновляли с сервера; по нему чистим через 2 месяца

    init(id: String, title: String, room: String, teacher: String,
         start: Date, end: Date, syncedAt: Date = .now) {
        self.id = id; self.title = title; self.room = room; self.teacher = teacher
        self.start = start; self.end = end; self.syncedAt = syncedAt
    }
}

@Model final class Cheat {
    var title: String
    var topic: String
    var body: String

    init(title: String, topic: String, body: String) {
        self.title = title; self.topic = topic; self.body = body
    }
}
