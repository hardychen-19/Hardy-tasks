import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI
import UserNotifications
import WidgetKit

struct SubtaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var done: Bool
    var createdAt: Date
    var updatedAt: Date?
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var deadline: Date?
    var done: Bool
    var createdAt: Date
    var notes: String?
    var priority: TaskPriority?
    var updatedAt: Date?
    var completedAt: Date?
    var subtasks: [SubtaskItem]? = nil
    var recurrence: TaskRecurrence? = nil
    var pinned: Bool? = nil
    var source: TaskSource? = nil
    var externalID: String? = nil
    var externalListID: String? = nil
    var externalUpdatedAt: Date? = nil
    var deadlineHasTime: Bool? = nil

    var taskPriority: TaskPriority {
        priority ?? .normal
    }

    var taskSubtasks: [SubtaskItem] {
        subtasks ?? []
    }

    var isPinned: Bool {
        pinned ?? false
    }

    var isGoogleTask: Bool {
        source == .google
    }

    var showsDeadlineTime: Bool {
        deadlineHasTime ?? true
    }

    var completedSubtaskCount: Int {
        taskSubtasks.filter(\.done).count
    }

    var subtaskProgressText: String? {
        guard !taskSubtasks.isEmpty else { return nil }
        return "\(completedSubtaskCount)/\(taskSubtasks.count) subtasks"
    }
}

enum TaskSource: String, Codable, Equatable {
    case google
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    var rank: Int {
        switch self {
        case .high: 0
        case .normal: 1
        case .low: 2
        }
    }

    var symbol: String {
        switch self {
        case .low: "arrow.down"
        case .normal: "equal"
        case .high: "exclamationmark"
        }
    }
}

enum TaskRecurrence: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "repeat"
        case .weekly: "calendar.badge.clock"
        case .monthly: "calendar"
        }
    }

    func nextDate(after deadline: Date, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let component: Calendar.Component = switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }

        var next = calendar.date(byAdding: component, value: 1, to: deadline) ?? now
        while next <= now {
            next = calendar.date(byAdding: component, value: 1, to: next) ?? now
        }
        return next
    }
}

enum ReminderOffset: Int, CaseIterable, Codable, Identifiable {
    case atDeadline = 0
    case fifteenMinutes = 900
    case oneHour = 3600
    case oneDay = 86400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .atDeadline: "At deadline"
        case .fifteenMinutes: "15 min before"
        case .oneHour: "1 hour before"
        case .oneDay: "1 day before"
        }
    }

    func fireDate(for deadline: Date) -> Date {
        deadline.addingTimeInterval(-TimeInterval(rawValue))
    }
}

struct NotificationSettings: Codable, Equatable {
    var enabled: Bool
    var reminderOffsets: [ReminderOffset]

    static let `default` = NotificationSettings(enabled: false, reminderOffsets: [.oneHour])
}

struct DeadlineAwarenessSettings: Codable, Equatable {
    var enabled: Bool
    var systemNotificationFallback: Bool
    var quietStartMinutes: Int
    var quietEndMinutes: Int

    static let `default` = DeadlineAwarenessSettings(
        enabled: true,
        systemNotificationFallback: false,
        quietStartMinutes: 23 * 60 + 30,
        quietEndMinutes: 7 * 60 + 30
    )
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct GoogleSyncSettings: Codable, Equatable {
    var clientID: String
    var isConnected: Bool
    var selectedTaskListID: String?
    var selectedTaskListTitle: String?
    var lastSyncedAt: Date?

    static let `default` = GoogleSyncSettings(
        clientID: "",
        isConnected: false,
        selectedTaskListID: nil,
        selectedTaskListTitle: nil,
        lastSyncedAt: nil
    )
}

struct AppSettings: Codable, Equatable {
    var notifications: NotificationSettings
    var appearance: AppearanceMode
    var googleSync: GoogleSyncSettings
    var deadlineAwareness: DeadlineAwarenessSettings

    static let `default` = AppSettings(
        notifications: .default,
        appearance: .system,
        googleSync: .default,
        deadlineAwareness: .default
    )

    private enum CodingKeys: String, CodingKey {
        case notifications
        case appearance
        case googleSync
        case deadlineAwareness
    }

    init(
        notifications: NotificationSettings,
        appearance: AppearanceMode,
        googleSync: GoogleSyncSettings,
        deadlineAwareness: DeadlineAwarenessSettings
    ) {
        self.notifications = notifications
        self.appearance = appearance
        self.googleSync = googleSync
        self.deadlineAwareness = deadlineAwareness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try container.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? .default
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .system
        googleSync = try container.decodeIfPresent(GoogleSyncSettings.self, forKey: .googleSync) ?? .default
        deadlineAwareness = try container.decodeIfPresent(DeadlineAwarenessSettings.self, forKey: .deadlineAwareness) ?? .default
    }
}

extension Notification.Name {
    static let quietTasksChanged = Notification.Name("quietTasks.tasksChanged")
}

enum SharedFiles {
    static var directory: URL {
        let directory = URL(fileURLWithPath: "/Users/Shared/QuietTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum TaskStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("tasks.json")
    }

    private static var legacyFileURLs: [URL] {
        let username = NSUserName()
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(username) ?? "/Users/\(username)", isDirectory: true)
        return [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/QuietTasks/tasks.json"),
            realHome
                .appendingPathComponent("Library/Application Support/QuietTasks/tasks.json"),
            realHome
                .appendingPathComponent("Library/Group Containers/group.com.rakeshutekar.quiettasksnative/QuietTasks/tasks.json")
        ].filter { $0 != fileURL }
    }

    static func load() -> [TaskItem] {
        let primaryTasks = decode(fileURL)
        if let tasks = primaryTasks, !tasks.isEmpty {
            return normalized(tasks)
        }

        if let legacyTasks = legacyFileURLs.compactMap(decode).first(where: { !$0.isEmpty }) {
            let tasks = normalized(legacyTasks)
            save(tasks)
            return tasks
        }

        return normalized(primaryTasks ?? [])
    }

    static func save(_ tasks: [TaskItem]) {
        guard let data = try? JSONEncoder.taskEncoder.encode(tasks) else { return }
        try? FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .quietTasksChanged, object: nil)
        }
    }

    private static func decode(_ url: URL) -> [TaskItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.taskDecoder.decode([TaskItem].self, from: data)
    }

    static func normalized(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.taskPriority.rank != rhs.taskPriority.rank { return lhs.taskPriority.rank < rhs.taskPriority.rank }
            switch (lhs.deadline, rhs.deadline) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

enum SettingsStore {
    static var fileURL: URL {
        SharedFiles.directory.appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .default
        }

        if let settings = try? JSONDecoder.taskDecoder.decode(AppSettings.self, from: data) {
            return normalized(settings)
        }

        if let legacyNotifications = try? JSONDecoder.taskDecoder.decode(NotificationSettings.self, from: data) {
            var settings = AppSettings.default
            settings.notifications = legacyNotifications
            return normalized(settings)
        }

        return .default
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder.taskEncoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: SharedFiles.directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func normalized(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        normalized.appearance = .system
        if normalized.notifications.enabled && normalized.notifications.reminderOffsets.isEmpty {
            normalized.notifications.reminderOffsets = [.oneHour]
        }
        normalized.googleSync.clientID = normalized.googleSync.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.deadlineAwareness.quietStartMinutes = min(max(normalized.deadlineAwareness.quietStartMinutes, 0), 1439)
        normalized.deadlineAwareness.quietEndMinutes = min(max(normalized.deadlineAwareness.quietEndMinutes, 0), 1439)
        return normalized
    }
}

enum NotificationScheduler {
    private static let identifierPrefix = "quiettasks.deadline."

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    static func sync(tasks: [TaskItem], settings: NotificationSettings) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let existingIdentifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: existingIdentifiers)

            guard settings.enabled else { return }

            for task in tasks where !task.done {
                guard let deadline = task.deadline else { continue }

                for offset in settings.reminderOffsets {
                    let fireDate = offset.fireDate(for: deadline)
                    guard fireDate > Date().addingTimeInterval(5) else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = task.title
                    content.body = offset == .atDeadline ? "Due now" : "Due \(offset.title.lowercased())"
                    content.sound = .default

                    let components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "\(identifierPrefix)\(task.id).\(offset.rawValue)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                }
            }
        }
    }

    static func sendDeadlineFallback(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .active
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension JSONDecoder {
    static var taskDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var taskEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct GoogleTaskList: Codable, Identifiable, Equatable {
    var id: String
    var title: String
}

struct GoogleTask: Codable, Identifiable {
    var id: String
    var title: String?
    var notes: String?
    var status: String?
    var due: Date?
    var updated: Date?
    var completed: Date?
    var parent: String?
}

struct GoogleTaskListResponse: Decodable {
    var items: [GoogleTaskList]?
    var nextPageToken: String?
}

struct GoogleTasksResponse: Decodable {
    var items: [GoogleTask]?
    var nextPageToken: String?
}

struct GoogleTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int?
    var refreshToken: String?
    var tokenType: String?
}

struct GoogleAccessToken {
    var value: String
    var expiresAt: Date
}

enum GoogleSyncError: LocalizedError {
    case missingClientID
    case missingRefreshToken
    case missingTaskList
    case invalidResponse
    case oauthCancelled
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            "Add a Google OAuth client ID first."
        case .missingRefreshToken:
            "Connect Google Tasks again."
        case .missingTaskList:
            "Choose a Google task list first."
        case .invalidResponse:
            "Google returned an unexpected response."
        case .oauthCancelled:
            "Google sign-in was cancelled."
        case let .apiError(message):
            message
        }
    }
}

enum GoogleDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }
}

extension JSONDecoder {
    static var googleDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = GoogleDateParser.parse(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Google date: \(value)"
            )
        }
        return decoder
    }
}

enum KeychainTokenStore {
    private static let service = "com.rakeshutekar.quiettasks.google"
    private static let account = "refresh-token"

    static func saveRefreshToken(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GoogleSyncError.apiError("Could not save Google token.")
        }
    }

    static func loadRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    static func deleteRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}

enum GoogleOAuthClient {
    static let scope = "https://www.googleapis.com/auth/tasks.readonly"
    private static let redirectURI = "com.rakeshutekar.quiettasks:/oauth2redirect"
    private static let callbackScheme = "com.rakeshutekar.quiettasks"
    private static var currentSession: ASWebAuthenticationSession?
    private static let presentationProvider = OAuthPresentationContextProvider()

    static func authorize(clientID: String) async throws -> GoogleAccessToken {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else { throw GoogleSyncError.missingClientID }

        let verifier = pkceVerifier()
        let challenge = pkceChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let authorizationURL = components.url else { throw GoogleSyncError.invalidResponse }
        let callbackURL = try await authenticate(url: authorizationURL)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
        else {
            throw GoogleSyncError.invalidResponse
        }

        let response = try await exchangeCode(
            code,
            clientID: trimmedClientID,
            verifier: verifier
        )
        if let refreshToken = response.refreshToken {
            try KeychainTokenStore.saveRefreshToken(refreshToken)
        }
        return GoogleAccessToken(
            value: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        )
    }

    static func refreshedAccessToken(clientID: String) async throws -> GoogleAccessToken {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else { throw GoogleSyncError.missingClientID }
        guard let refreshToken = KeychainTokenStore.loadRefreshToken() else {
            throw GoogleSyncError.missingRefreshToken
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": trimmedClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let response = try await tokenResponse(for: request)
        return GoogleAccessToken(
            value: response.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        )
    }

    private static func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                currentSession = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSyncError.oauthCancelled)
                    return
                }

                continuation.resume(throwing: error ?? GoogleSyncError.invalidResponse)
            }
            session.presentationContextProvider = presentationProvider
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            session.start()
        }
    }

    private static func exchangeCode(
        _ code: String,
        clientID: String,
        verifier: String
    ) async throws -> GoogleTokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ])
        return try await tokenResponse(for: request)
    }

    private static func tokenResponse(for request: URLRequest) async throws -> GoogleTokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleSyncError.apiError(apiErrorMessage(from: data) ?? "Google sign-in failed.")
        }
        return try JSONDecoder.googleDecoder.decode(GoogleTokenResponse.self, from: data)
    }

    private static func pkceVerifier() -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<64).compactMap { _ in characters.randomElement() })
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncoded(_ values: [String: String]) -> Data? {
        let query = values
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        return Data(query.utf8)
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String
        else {
            return nil
        }
        if let description = object["error_description"] as? String {
            return "\(error): \(description)"
        }
        return error
    }
}

enum GoogleTasksClient {
    static func fetchTaskLists(accessToken: String) async throws -> [GoogleTaskList] {
        var lists: [GoogleTaskList] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await googleResponse(GoogleTaskListResponse.self, for: request)
            lists.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return lists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func fetchTasks(
        accessToken: String,
        taskListID: String,
        taskListTitle: String?
    ) async throws -> [TaskItem] {
        var googleTasks: [GoogleTask] = []
        var pageToken: String?

        repeat {
            let encodedListID = taskListID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListID
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/\(encodedListID)/tasks")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "100"),
                URLQueryItem(name: "showCompleted", value: "true"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "showHidden", value: "true")
            ]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let response = try await googleResponse(GoogleTasksResponse.self, for: request)
            googleTasks.append(contentsOf: response.items ?? [])
            pageToken = response.nextPageToken
        } while pageToken != nil

        return mappedTasks(from: googleTasks, taskListID: taskListID, taskListTitle: taskListTitle)
    }

    private static func googleResponse<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleSyncError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GoogleSyncError.apiError(apiErrorMessage(from: data) ?? "Google Tasks request failed.")
        }
        return try JSONDecoder.googleDecoder.decode(T.self, from: data)
    }

    private static func mappedTasks(
        from googleTasks: [GoogleTask],
        taskListID: String,
        taskListTitle: String?
    ) -> [TaskItem] {
        let childTasks = Dictionary(grouping: googleTasks.filter { $0.parent != nil }) { task in
            task.parent ?? ""
        }

        return googleTasks
            .filter { $0.parent == nil }
            .map { task in
                let subtasks = (childTasks[task.id] ?? []).map { child in
                    SubtaskItem(
                        id: googleID(listID: taskListID, taskID: child.id),
                        title: cleanedTitle(child.title),
                        done: child.status == "completed",
                        createdAt: child.updated ?? Date(),
                        updatedAt: child.updated
                    )
                }

                return TaskItem(
                    id: googleID(listID: taskListID, taskID: task.id),
                    title: cleanedTitle(task.title),
                    deadline: task.due,
                    done: task.status == "completed",
                    createdAt: task.updated ?? Date(),
                    notes: task.notes,
                    priority: .normal,
                    updatedAt: task.updated,
                    completedAt: task.completed,
                    subtasks: subtasks.isEmpty ? nil : subtasks,
                    recurrence: nil,
                    pinned: nil,
                    source: .google,
                    externalID: task.id,
                    externalListID: taskListID,
                    externalUpdatedAt: task.updated,
                    deadlineHasTime: false
                )
            }
    }

    private static func googleID(listID: String, taskID: String) -> String {
        "google:\(listID):\(taskID)"
    }

    private static func cleanedTitle(_ title: String?) -> String {
        let trimmed = (title ?? "Untitled Google task").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Google task" : trimmed
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return message
            }
            if let status = error["status"] as? String {
                return status
            }
        }
        if let error = object["error"] as? String {
            return error
        }
        return nil
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case open
    case today
    case all
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .today: "Today"
        case .all: "All Tasks"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .open: "tray"
        case .today: "calendar"
        case .all: "list.bullet"
        case .done: "checkmark.circle"
        }
    }
}

@MainActor
final class TaskModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem]
    @Published private(set) var settings: AppSettings
    @Published private(set) var googleTaskLists: [GoogleTaskList] = []
    @Published private(set) var isGoogleBusy = false
    @Published var googleStatus: String?

    var notificationSettings: NotificationSettings {
        settings.notifications
    }

    init() {
        tasks = TaskStore.load()
        settings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var openTasks: [TaskItem] {
        tasks.filter { !$0.done }
    }

    var completedCount: Int {
        tasks.filter(\.done).count
    }

    var progress: Double {
        guard displayTotalCount > 0 else { return 0 }
        return Double(displayCompletedCount) / Double(displayTotalCount)
    }

    var displayCompletedCount: Int {
        openTasks.isEmpty ? 0 : completedCount
    }

    var displayTotalCount: Int {
        openTasks.isEmpty ? 0 : tasks.count
    }

    func reload() {
        tasks = TaskStore.load()
        settings = SettingsStore.load()
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func add(
        title: String,
        notes: String = "",
        deadline: Date?,
        priority: TaskPriority,
        recurrence: TaskRecurrence?,
        pinned: Bool
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks.insert(TaskItem(
            id: UUID().uuidString,
            title: trimmed,
            deadline: deadline,
            done: false,
            createdAt: Date(),
            notes: cleanNotes.isEmpty ? nil : cleanNotes,
            priority: priority,
            updatedAt: nil,
            completedAt: nil,
            subtasks: nil,
            recurrence: deadline == nil ? nil : recurrence,
            pinned: pinned ? true : nil,
            deadlineHasTime: deadline == nil ? nil : true
        ), at: 0)
        persist()
    }

    func update(
        _ task: TaskItem,
        title: String,
        notes: String,
        deadline: Date?,
        priority: TaskPriority,
        subtasks: [SubtaskItem],
        recurrence: TaskRecurrence?,
        pinned: Bool
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            guard !item.isGoogleTask else { return item }
            var updated = item
            updated.title = trimmed
            updated.notes = cleanNotes.isEmpty ? nil : cleanNotes
            updated.deadline = deadline
            updated.priority = priority
            updated.subtasks = subtasks.isEmpty ? nil : subtasks
            updated.recurrence = deadline == nil ? nil : recurrence
            updated.pinned = pinned ? true : nil
            updated.deadlineHasTime = deadline == nil ? nil : true
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func markDone(_ task: TaskItem) {
        guard !task.isGoogleTask else {
            googleStatus = "Google tasks are read-only. Complete this in Google Tasks."
            return
        }
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            if let recurrence = item.recurrence, let deadline = item.deadline {
                updated.deadline = recurrence.nextDate(after: deadline)
                updated.subtasks = item.taskSubtasks.map { subtask in
                    var reset = subtask
                    reset.done = false
                    reset.updatedAt = Date()
                    return reset
                }
                updated.updatedAt = Date()
                return updated
            }
            updated.done = true
            updated.completedAt = Date()
            updated.updatedAt = Date()
            updated.subtasks = item.taskSubtasks.map { subtask in
                var completed = subtask
                completed.done = true
                completed.updatedAt = Date()
                return completed
            }
            return updated
        }
        persist()
    }

    func restore(_ task: TaskItem) {
        guard !task.isGoogleTask else {
            googleStatus = "Google tasks are read-only. Restore this in Google Tasks."
            return
        }
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.done = false
            updated.completedAt = nil
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func delete(_ task: TaskItem) {
        guard !task.isGoogleTask else {
            googleStatus = "Google tasks are read-only. Remove this in Google Tasks."
            return
        }
        tasks.removeAll { $0.id == task.id }
        persist()
    }

    func togglePinned(_ task: TaskItem) {
        guard !task.isGoogleTask else {
            googleStatus = "Google tasks are read-only. Pin local tasks in Quiet Tasks."
            return
        }
        tasks = tasks.map { item in
            guard item.id == task.id else { return item }
            var updated = item
            updated.pinned = item.isPinned ? nil : true
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func toggleSubtask(taskID: String, subtaskID: String) {
        tasks = tasks.map { item in
            guard item.id == taskID else { return item }
            guard !item.isGoogleTask else {
                googleStatus = "Google subtasks are read-only. Update them in Google Tasks."
                return item
            }
            var updated = item
            updated.subtasks = item.taskSubtasks.map { subtask in
                guard subtask.id == subtaskID else { return subtask }
                var changed = subtask
                changed.done.toggle()
                changed.updatedAt = Date()
                return changed
            }
            updated.updatedAt = Date()
            return updated
        }
        persist()
    }

    func updateNotificationSettings(_ settings: NotificationSettings) {
        if settings.enabled {
            NotificationScheduler.requestAuthorization { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    let savedSettings = NotificationSettings(
                        enabled: granted,
                        reminderOffsets: settings.reminderOffsets.isEmpty ? [.oneHour] : settings.reminderOffsets
                    )
                    self.settings.notifications = savedSettings
                    SettingsStore.save(self.settings)
                    NotificationScheduler.sync(tasks: self.tasks, settings: savedSettings)
                }
            }
        } else {
            self.settings.notifications = settings
            SettingsStore.save(self.settings)
            NotificationScheduler.sync(tasks: tasks, settings: settings)
        }
    }

    func updateAppearance(_ appearance: AppearanceMode) {
        settings.appearance = appearance
        SettingsStore.save(settings)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateDeadlineAwarenessSettings(_ deadlineAwareness: DeadlineAwarenessSettings) {
        settings.deadlineAwareness = deadlineAwareness
        SettingsStore.save(settings)
        NotificationCenter.default.post(name: .quietTasksChanged, object: nil)
        if deadlineAwareness.enabled && deadlineAwareness.systemNotificationFallback {
            NotificationScheduler.requestAuthorization { _ in }
        }
    }

    func updateGoogleSettings(_ googleSettings: GoogleSyncSettings) {
        settings.googleSync = googleSettings
        SettingsStore.save(settings)
    }

    func connectGoogle(clientID: String) async {
        await runGoogleOperation {
            var googleSettings = self.settings.googleSync
            googleSettings.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.settings.googleSync = googleSettings
            SettingsStore.save(self.settings)

            let token = try await GoogleOAuthClient.authorize(clientID: googleSettings.clientID)
            googleSettings.isConnected = true
            self.settings.googleSync = googleSettings
            SettingsStore.save(self.settings)
            try await self.loadGoogleTaskLists(accessToken: token.value)
            self.googleStatus = "Google Tasks connected."
        }
    }

    func loadGoogleTaskLists() async {
        await runGoogleOperation {
            let token = try await GoogleOAuthClient.refreshedAccessToken(clientID: self.settings.googleSync.clientID)
            try await self.loadGoogleTaskLists(accessToken: token.value)
            self.googleStatus = "Google task lists refreshed."
        }
    }

    func syncGoogleTasks() async {
        await runGoogleOperation {
            let googleSettings = self.settings.googleSync
            guard let taskListID = googleSettings.selectedTaskListID else {
                throw GoogleSyncError.missingTaskList
            }

            let token = try await GoogleOAuthClient.refreshedAccessToken(clientID: googleSettings.clientID)
            let syncedTasks = try await GoogleTasksClient.fetchTasks(
                accessToken: token.value,
                taskListID: taskListID,
                taskListTitle: googleSettings.selectedTaskListTitle
            )
            self.tasks.removeAll { $0.source == .google }
            self.tasks.append(contentsOf: syncedTasks)
            self.settings.googleSync.lastSyncedAt = Date()
            SettingsStore.save(self.settings)
            self.persist()
            self.googleStatus = "Synced \(syncedTasks.count) Google tasks."
        }
    }

    func disconnectGoogle() {
        KeychainTokenStore.deleteRefreshToken()
        tasks.removeAll { $0.source == .google }
        googleTaskLists = []
        settings.googleSync = .default
        SettingsStore.save(settings)
        persist()
        googleStatus = "Google Tasks disconnected."
    }

    func selectGoogleTaskList(_ list: GoogleTaskList) {
        settings.googleSync.selectedTaskListID = list.id
        settings.googleSync.selectedTaskListTitle = list.title
        SettingsStore.save(settings)
    }

    func tasks(for filter: TaskFilter, search: String) -> [TaskItem] {
        let calendar = Calendar.current
        let searched = tasks.filter { task in
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return task.title.localizedCaseInsensitiveContains(query)
                || (task.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }

        switch filter {
        case .open:
            return searched.filter { !$0.done }
        case .today:
            return searched.filter { task in
                guard !task.done else { return false }
                guard let deadline = task.deadline else { return false }
                return calendar.isDateInToday(deadline)
            }
        case .all:
            return searched
        case .done:
            return searched.filter(\.done)
        }
    }

    private func persist() {
        tasks = TaskStore.normalized(tasks)
        TaskStore.save(tasks)
        NotificationScheduler.sync(tasks: tasks, settings: notificationSettings)
    }

    private func loadGoogleTaskLists(accessToken: String) async throws {
        let lists = try await GoogleTasksClient.fetchTaskLists(accessToken: accessToken)
        googleTaskLists = lists

        if settings.googleSync.selectedTaskListID == nil, let first = lists.first {
            selectGoogleTaskList(first)
        } else if let selectedID = settings.googleSync.selectedTaskListID,
                  let selected = lists.first(where: { $0.id == selectedID }) {
            settings.googleSync.selectedTaskListTitle = selected.title
            SettingsStore.save(settings)
        }
    }

    private func runGoogleOperation(_ operation: @escaping () async throws -> Void) async {
        guard !isGoogleBusy else { return }
        isGoogleBusy = true
        googleStatus = nil
        do {
            try await operation()
        } catch {
            googleStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isGoogleBusy = false
    }
}

struct TaskDraft: Identifiable {
    var id = UUID()
    var task: TaskItem?
    var title: String
    var notes: String
    var hasDeadline: Bool
    var deadline: Date
    var priority: TaskPriority
    var subtasks: [SubtaskItem]
    var recurrence: TaskRecurrence?
    var pinned: Bool

    init(task: TaskItem? = nil) {
        self.task = task
        title = task?.title ?? ""
        notes = task?.notes ?? ""
        hasDeadline = task?.deadline != nil
        deadline = task?.deadline ?? Date()
        priority = task?.taskPriority ?? .normal
        subtasks = task?.taskSubtasks ?? []
        recurrence = task?.recurrence
        pinned = task?.isPinned ?? false
    }
}

struct TaskWorkspaceView: View {
    @StateObject private var model = TaskModel()
    @State private var selectedFilter: TaskFilter = .open
    @State private var search = ""
    @State private var newTitle = ""
    @State private var newDeadline = Date()
    @State private var newHasDeadline = false
    @State private var newPriority: TaskPriority = .normal
    @State private var newRecurrence: TaskRecurrence?
    @State private var newPinned = false
    @State private var pendingCompletion: TaskItem?
    @State private var pendingDeletion: TaskItem?
    @State private var pendingReadOnlyGoogleTask: TaskItem?
    @State private var editingDraft: TaskDraft?
    @State private var showingSettings = false
    @FocusState private var newTaskFocused: Bool

    var visibleTasks: [TaskItem] {
        model.tasks(for: selectedFilter, search: search)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedFilter) {
                Section("Views") {
                    ForEach(TaskFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbol)
                            .tag(filter)
                    }
                }

                Section("Progress") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(model.displayCompletedCount) / \(model.displayTotalCount) done")
                            .font(.headline)
                        ProgressView(value: model.progress)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Quiet Tasks")
            .frame(minWidth: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 28)
                    .padding(.top, 26)
                    .padding(.bottom, 18)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        addComposer

                        if visibleTasks.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 90)
                        } else {
                            taskList
                        }
                    }
                    .padding(28)
                }
            }
            .workspaceContentSurface()
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tasks")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    selectedFilter = .open
                    newTaskFocused = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                Button {
                    model.reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onOpenURL(perform: handleURL)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
        .alert("Complete task?", isPresented: Binding(
            get: { pendingCompletion != nil },
            set: { if !$0 { pendingCompletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingCompletion = nil
            }
            Button("Complete") {
                if let task = pendingCompletion {
                    model.markDone(task)
                }
                pendingCompletion = nil
            }
        } message: {
            Text(pendingCompletion?.title ?? "")
        }
        .alert("Delete task?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let task = pendingDeletion {
                    model.delete(task)
                }
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion?.title ?? "")
        }
        .alert("Google task is read-only", isPresented: Binding(
            get: { pendingReadOnlyGoogleTask != nil },
            set: { if !$0 { pendingReadOnlyGoogleTask = nil } }
        )) {
            Button("OK") {
                pendingReadOnlyGoogleTask = nil
            }
        } message: {
            Text("Update “\(pendingReadOnlyGoogleTask?.title ?? "this task")” in Google Tasks. Quiet Tasks is only reading Google tasks in this version.")
        }
        .sheet(item: $editingDraft) { draft in
            TaskEditSheet(draft: draft) { updatedDraft in
                guard let task = updatedDraft.task else { return }
                model.update(
                    task,
                    title: updatedDraft.title,
                    notes: updatedDraft.notes,
                    deadline: updatedDraft.hasDeadline ? updatedDraft.deadline : nil,
                    priority: updatedDraft.priority,
                    subtasks: updatedDraft.subtasks,
                    recurrence: updatedDraft.hasDeadline ? updatedDraft.recurrence : nil,
                    pinned: updatedDraft.pinned
                )
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(model: model) {
                showingSettings = false
            }
        }
        .frame(minWidth: 880, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedFilter.title)
                    .font(.largeTitle.bold())
                Text(summaryText)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(progress: model.progress)
                .frame(width: 54, height: 54)
        }
    }

    private var summaryText: String {
        if model.tasks.isEmpty { return "No tasks yet" }
        if model.openTasks.isEmpty { return "All clear" }
        return "\(model.openTasks.count) open, \(model.completedCount) done"
    }

    private var addComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Add a task", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($newTaskFocused)
                    .onSubmit(addTask)

                Button(action: addTask) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    DueDateControl(isEnabled: $newHasDeadline, date: $newDeadline)
                        .frame(minWidth: 210, alignment: .leading)
                    PriorityPicker(priority: $newPriority)
                }

                HStack(spacing: 18) {
                    RecurrencePicker(recurrence: $newRecurrence, isEnabled: newHasDeadline)
                    PinToggle(isPinned: $newPinned)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var taskList: some View {
        LazyVStack(spacing: 10) {
            ForEach(visibleTasks) { task in
                TaskRow(
                    task: task,
                    onComplete: { requestCompletion(for: task) },
                    onRestore: { model.restore(task) },
                    onEdit: { editingDraft = TaskDraft(task: task) },
                    onDelete: { pendingDeletion = task },
                    onTogglePinned: { model.togglePinned(task) },
                    onToggleSubtask: { subtask in
                        model.toggleSubtask(taskID: task.id, subtaskID: subtask.id)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedFilter == .done ? "arrow.uturn.backward.circle" : "checkmark.circle")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(selectedFilter == .done ? "No completed tasks" : "No tasks here")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func addTask() {
        model.add(
            title: newTitle,
            deadline: newHasDeadline ? newDeadline : nil,
            priority: newPriority,
            recurrence: newHasDeadline ? newRecurrence : nil,
            pinned: newPinned
        )
        newTitle = ""
        newHasDeadline = false
        newPriority = .normal
        newRecurrence = nil
        newPinned = false
        selectedFilter = .open
        newTaskFocused = true
    }

    private func requestCompletion(for task: TaskItem) {
        if task.isGoogleTask {
            pendingReadOnlyGoogleTask = task
        } else {
            pendingCompletion = task
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "quiettasks" else { return }

        switch url.host {
        case "add":
            selectedFilter = .open
            newTaskFocused = true
        case "complete":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value
            model.reload()
            if let task = model.tasks.first(where: { $0.id == id && !$0.done }) {
                requestCompletion(for: task)
            }
        case "google":
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "id" }?
                .value
            model.reload()
            pendingReadOnlyGoogleTask = model.tasks.first { $0.id == id }
        case "subtask":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let taskID = components?
                .queryItems?
                .first { $0.name == "task" }?
                .value
            let subtaskID = components?
                .queryItems?
                .first { $0.name == "subtask" }?
                .value
            if let taskID, let subtaskID {
                model.toggleSubtask(taskID: taskID, subtaskID: subtaskID)
            }
        default:
            break
        }
    }
}

struct TaskRow: View {
    var task: TaskItem
    var onComplete: () -> Void
    var onRestore: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onTogglePinned: () -> Void
    var onToggleSubtask: (SubtaskItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: task.done ? onRestore : onComplete) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? .green : Color(red: 0.62, green: 0.86, blue: 0.88))
            }
            .buttonStyle(.plain)
            .help(task.isGoogleTask ? "Open Google Tasks to update" : (task.done ? "Restore" : "Complete"))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if task.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
                    }

                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                }

                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if task.isGoogleTask {
                        SourceBadge(title: "Google")
                    } else {
                        PriorityBadge(priority: task.taskPriority)
                    }
                    if let deadline = task.deadline {
                        Label(deadlineText(deadline), systemImage: "calendar")
                    }
                    if let recurrence = task.recurrence {
                        Label(recurrence.title, systemImage: recurrence.symbol)
                    }
                    if let subtaskProgressText = task.subtaskProgressText {
                        Label(subtaskProgressText, systemImage: "checklist")
                    }
                    Label(task.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "plus.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !task.taskSubtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(task.taskSubtasks) { subtask in
                            Button {
                                onToggleSubtask(subtask)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: subtask.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(subtask.done ? .green : Color(red: 0.62, green: 0.86, blue: 0.88))
                                    Text(subtask.title)
                                        .strikethrough(subtask.done)
                                        .foregroundStyle(subtask.done ? .secondary : .primary)
                                        .lineLimit(1)
                                }
                                .font(.callout)
                            }
                            .buttonStyle(.plain)
                            .disabled(task.isGoogleTask)
                            .help(subtask.done ? "Restore subtask" : "Complete subtask")
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(action: onTogglePinned) {
                    Image(systemName: task.isPinned ? "pin.fill" : "pin")
                }
                .help(task.isPinned ? "Unpin" : "Pin")
                .disabled(task.isGoogleTask)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .help("Edit")
                .disabled(task.isGoogleTask)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .help("Delete")
                .disabled(task.isGoogleTask)
            }
            .buttonStyle(.borderless)
            .font(.title3)
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func deadlineText(_ deadline: Date) -> String {
        if task.showsDeadlineTime {
            return deadline.formatted(date: .abbreviated, time: .shortened)
        }
        return deadline.formatted(date: .abbreviated, time: .omitted)
    }
}

struct TaskEditSheet: View {
    @State var draft: TaskDraft
    @State private var newSubtaskTitle = ""
    var onSave: (TaskDraft) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Task")
                .font(.title.bold())

            TextField("Task", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            TextField("Notes", text: $draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            VStack(alignment: .leading, spacing: 14) {
                DueDateControl(isEnabled: $draft.hasDeadline, date: $draft.deadline)
                PriorityPicker(priority: $draft.priority)
                RecurrencePicker(recurrence: $draft.recurrence, isEnabled: draft.hasDeadline)
                PinToggle(isPinned: $draft.pinned)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Subtasks", systemImage: "checklist")
                    .font(.headline)

                ForEach($draft.subtasks) { $subtask in
                    HStack(spacing: 8) {
                        Toggle("", isOn: $subtask.done)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        TextField("Subtask", text: $subtask.title)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            draft.subtasks.removeAll { $0.id == subtask.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete subtask")
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add subtask", text: $newSubtaskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSubtask)
                    Button(action: addSubtask) {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    saveDraft()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.subtasks.append(SubtaskItem(
            id: UUID().uuidString,
            title: trimmed,
            done: false,
            createdAt: Date(),
            updatedAt: nil
        ))
        newSubtaskTitle = ""
    }

    private func saveDraft() {
        draft.subtasks = draft.subtasks.compactMap { subtask in
            let trimmed = subtask.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var cleaned = subtask
            cleaned.title = trimmed
            cleaned.updatedAt = Date()
            return cleaned
        }
        if !draft.hasDeadline {
            draft.recurrence = nil
        }
        onSave(draft)
    }
}

struct DueDateControl: View {
    @Binding var isEnabled: Bool
    @Binding var date: Date
    @State private var showingPopover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Deadline", isOn: $isEnabled)
                .toggleStyle(.checkbox)
                .fixedSize()

            if isEnabled {
                Button {
                    showingPopover.toggle()
                } label: {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
                    deadlinePopover
                }

                Button {
                    isEnabled = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear deadline")
            } else {
                Button {
                    isEnabled = true
                    date = Date()
                    showingPopover = true
                } label: {
                    Label("Set date", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var deadlinePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deadline")
                .font(.headline)

            DatePicker("Date", selection: $date, displayedComponents: .date)
            DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)

            Divider()

            HStack(spacing: 8) {
                Button("Today") {
                    date = Date()
                    isEnabled = true
                }
                Button("Tomorrow") {
                    date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    isEnabled = true
                }
                Button("Next Week") {
                    date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    isEnabled = true
                }
            }

            HStack {
                Button("Clear") {
                    isEnabled = false
                    showingPopover = false
                }
                Spacer()
                Button("Done") {
                    showingPopover = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct PriorityPicker: View {
    @Binding var priority: TaskPriority

    var body: some View {
        HStack(spacing: 8) {
            Label("Priority", systemImage: "flag")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Picker("", selection: $priority) {
                ForEach(TaskPriority.allCases) { priority in
                    Text(priority.title)
                        .tag(priority)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .frame(minWidth: 280, alignment: .leading)
    }
}

struct RecurrencePicker: View {
    @Binding var recurrence: TaskRecurrence?
    var isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label("Repeats", systemImage: "repeat")
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .lineLimit(1)
                .fixedSize()

            Picker("", selection: $recurrence) {
                Text("None").tag(TaskRecurrence?.none)
                ForEach(TaskRecurrence.allCases) { recurrence in
                    Text(recurrence.title)
                        .tag(Optional(recurrence))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 240)
            .disabled(!isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    recurrence = nil
                }
            }
        }
        .frame(minWidth: 330, alignment: .leading)
    }
}

struct PinToggle: View {
    @Binding var isPinned: Bool

    var body: some View {
        Toggle(isOn: $isPinned) {
            Label("Pin", systemImage: isPinned ? "pin.fill" : "pin")
        }
        .toggleStyle(.checkbox)
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: TaskModel
    @State private var draft: AppSettings
    var onDone: () -> Void

    init(model: TaskModel, onDone: @escaping () -> Void) {
        self.model = model
        _draft = State(initialValue: model.settings)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title.bold())

            notificationSection
            Divider()
            deadlineAwarenessSection
            Divider()
            googleSection

            if let status = model.googleStatus {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Done") {
                    saveSettings()
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Notifications", isOn: $draft.notifications.enabled)
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Text("Default reminders")
                    .font(.headline)

                ForEach(ReminderOffset.allCases) { offset in
                    Toggle(offset.title, isOn: reminderBinding(for: offset))
                        .toggleStyle(.checkbox)
                        .disabled(!draft.notifications.enabled)
                }
            }
        }
        .onChange(of: draft.notifications) { _, notifications in
            model.updateNotificationSettings(notifications)
        }
    }

    private var deadlineAwarenessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Deadline waves", isOn: $draft.deadlineAwareness.enabled)
                .toggleStyle(.switch)

            Toggle("System notification fallback", isOn: $draft.deadlineAwareness.systemNotificationFallback)
                .toggleStyle(.checkbox)
                .disabled(!draft.deadlineAwareness.enabled)

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview urgency")
                    .font(.headline)
                HStack(spacing: 10) {
                    wavePreviewButton("Blue", value: "approaching", color: .blue)
                    wavePreviewButton("Orange", value: "urgent", color: .orange)
                    wavePreviewButton("Red", value: "overdue", color: .red)
                }
            }

            Text("Quiet from 23:30 to 07:30. Full-screen work is never interrupted; one combined reminder appears after you leave full screen or quiet hours end.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: draft.deadlineAwareness) { _, _ in
            model.updateDeadlineAwarenessSettings(draft.deadlineAwareness)
        }
    }

    private func wavePreviewButton(_ title: String, value: String, color: Color) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .quietTasksPreviewDeadlineWave,
                object: value
            )
        } label: {
            Label(title, systemImage: "wave.3.right")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Google Tasks", systemImage: "g.circle")
                    .font(.headline)
                Spacer()
                if model.isGoogleBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Read-only sync imports Google Tasks into the app and widget. Quiet Tasks will not edit Google Tasks yet.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("OAuth client ID", text: $draft.googleSync.clientID)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isGoogleBusy)

            HStack(spacing: 10) {
                if draft.googleSync.isConnected {
                    Button {
                        saveSettings()
                        Task { await model.loadGoogleTaskLists() }
                    } label: {
                        Label("Refresh Lists", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isGoogleBusy)

                    Button {
                        saveSettings()
                        Task { await model.syncGoogleTasks() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isGoogleBusy || draft.googleSync.selectedTaskListID == nil)

                    Button(role: .destructive) {
                        model.disconnectGoogle()
                        draft.googleSync = model.settings.googleSync
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(model.isGoogleBusy)
                } else {
                    Button {
                        saveSettings()
                        Task { await model.connectGoogle(clientID: draft.googleSync.clientID) }
                    } label: {
                        Label("Connect Google", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isGoogleBusy || draft.googleSync.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if draft.googleSync.isConnected {
                googleListPicker
                if let lastSyncedAt = draft.googleSync.lastSyncedAt {
                    Text("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.settings.googleSync) { _, googleSync in
            draft.googleSync = googleSync
        }
    }

    private var googleListPicker: some View {
        HStack(spacing: 10) {
            Label("Task list", systemImage: "list.bullet.rectangle")
                .foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { draft.googleSync.selectedTaskListID ?? "" },
                set: { selectedID in
                    guard let list = model.googleTaskLists.first(where: { $0.id == selectedID }) else { return }
                    draft.googleSync.selectedTaskListID = list.id
                    draft.googleSync.selectedTaskListTitle = list.title
                    model.selectGoogleTaskList(list)
                }
            )) {
                if model.googleTaskLists.isEmpty {
                    Text(draft.googleSync.selectedTaskListTitle ?? "No lists loaded").tag(draft.googleSync.selectedTaskListID ?? "")
                } else {
                    ForEach(model.googleTaskLists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .disabled(model.googleTaskLists.isEmpty || model.isGoogleBusy)
        }
    }

    private func saveSettings() {
        draft.notifications.reminderOffsets.sort { $0.rawValue < $1.rawValue }
        if draft.notifications.enabled && draft.notifications.reminderOffsets.isEmpty {
            draft.notifications.reminderOffsets = [.oneHour]
        }
        model.updateNotificationSettings(draft.notifications)
        model.updateDeadlineAwarenessSettings(draft.deadlineAwareness)
        model.updateGoogleSettings(draft.googleSync)
    }

    private func reminderBinding(for offset: ReminderOffset) -> Binding<Bool> {
        Binding(
            get: {
                draft.notifications.reminderOffsets.contains(offset)
            },
            set: { enabled in
                if enabled {
                    if !draft.notifications.reminderOffsets.contains(offset) {
                        draft.notifications.reminderOffsets.append(offset)
                    }
                } else {
                    draft.notifications.reminderOffsets.removeAll { $0 == offset }
                }
            }
        )
    }
}

struct PriorityBadge: View {
    var priority: TaskPriority

    var body: some View {
        Label(priority.title, systemImage: priority.symbol)
            .font(.caption.bold())
            .foregroundStyle(priority == .high ? Color(red: 0.95, green: 0.54, blue: 0.42) : .secondary)
    }
}

struct SourceBadge: View {
    var title: String

    var body: some View {
        Label(title, systemImage: "link")
            .font(.caption.bold())
            .foregroundStyle(Color(red: 0.62, green: 0.86, blue: 0.88))
    }
}

struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color(red: 0.62, green: 0.86, blue: 0.88), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.bold())
                .monospacedDigit()
        }
    }
}

@main
struct QuietTasksApp: App {
    @NSApplicationDelegateAdaptor(QuietTasksAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootWorkspaceView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
