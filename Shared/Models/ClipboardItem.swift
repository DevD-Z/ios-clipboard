import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var text: String
    let createdAt: Date
    var isFavorite: Bool
    var modifiedAt: Date
    var isDeleted: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, isFavorite: Bool = false,
         modifiedAt: Date? = nil, isDeleted: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.modifiedAt = modifiedAt ?? createdAt
        self.isDeleted = isDeleted
    }

    private enum CodingKeys: String, CodingKey { case id, text, createdAt, isFavorite, modifiedAt, isDeleted }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        // The original app's JSON backups did not contain sync metadata.
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        isDeleted = try values.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
}

extension Array where Element == ClipboardItem {
    /// Most recent first; UUID makes equal timestamps deterministic.
    func newestFirst() -> [ClipboardItem] {
        sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
