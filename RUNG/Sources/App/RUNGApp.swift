import SwiftUI
import UserNotifications

@main
struct RUNGApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .task { store.bootstrap() }
        }
    }
}

/// Local (no server push) once-a-day reminder. Calm, never fear-baiting (brand §9):
/// exactly one respectful notification, opt-in.
enum NotificationService {
    private static let dailyID = "rung.daily"

    static func requestAndSchedule() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted { scheduleDaily() }
        }
    }

    static func scheduleDailyIfAuthorized() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized { scheduleDaily() }
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyID])
    }

    private static func scheduleDaily() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyID])
        let content = UNMutableNotificationContent()
        content.title = "RUNG"
        content.body = "Today's board is live."
        content.sound = .default
        var when = DateComponents()
        when.hour = 9   // 9am local, repeating daily
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
    }
}
