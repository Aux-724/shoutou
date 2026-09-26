import Foundation

public struct Subtask: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool

    public init(id: UUID, title: String, isDone: Bool) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

public struct Quest: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var subtasks: [Subtask]
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public enum Status: String, Codable, Sendable {
        case active
        case parked
        case done
    }

    public var openSubtasks: [Subtask] {
        subtasks.filter { !$0.isDone }
    }

    public init(
        id: UUID,
        title: String,
        subtasks: [Subtask],
        status: Status,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.subtasks = subtasks
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case nextStep
        case subtasks
        case status
        case createdAt
        case updatedAt
        case completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(Status.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        if let subtasks = try container.decodeIfPresent([Subtask].self, forKey: .subtasks) {
            self.subtasks = subtasks
        } else {
            let legacy = try container.decodeIfPresent(String.self, forKey: .nextStep) ?? ""
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                subtasks = []
            } else {
                subtasks = [Subtask(id: UUID(), title: trimmed, isDone: false)]
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encode(status, forKey: .status)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}
