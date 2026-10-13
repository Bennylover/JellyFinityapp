import Foundation

/// A person credited on a movie or episode (actor, director, writer…).
struct CastMember: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable {
        case actor, director, writer, producer, other

        var title: String {
            switch self {
            case .actor: "Cast"
            case .director: "Directors"
            case .writer: "Writers"
            case .producer: "Producers"
            case .other: "Crew"
            }
        }
    }

    let id: String
    let name: String
    var character: String? = nil
    var role: Role = .actor
    var imageURL: URL? = nil

    /// Initials shown when the server has no portrait.
    var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    /// Short caption under the name: the character for actors, the job for crew.
    var caption: String? {
        if let character, !character.isEmpty { return character }
        return role == .actor ? nil : String(role.title.dropLast())
    }

    init(id: String, name: String, character: String? = nil, role: Role = .actor, imageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.role = role
        self.imageURL = imageURL
    }

    init(typeName: String?, id: String, name: String, character: String?, imageURL: URL?) {
        let role: Role = switch typeName {
        case "Actor", "GuestStar": .actor
        case "Director": .director
        case "Writer": .writer
        case "Producer": .producer
        default: .other
        }
        self.init(id: id, name: name, character: character, role: role, imageURL: imageURL)
    }
}

extension CastMember {
    /// Placeholder credits so demo mode shows the cast section.
    static let demo: [CastMember] = [
        CastMember(id: "demo-1", name: "Maya Lindqvist", character: "Dr. Elena Voss"),
        CastMember(id: "demo-2", name: "Daniel Okafor", character: "Captain Reyes"),
        CastMember(id: "demo-3", name: "Sofia Marchetti", character: "Nora"),
        CastMember(id: "demo-4", name: "Kenji Watanabe", character: "Hiro"),
        CastMember(id: "demo-5", name: "Amara Singh", character: "Lieutenant Rao"),
        CastMember(id: "demo-6", name: "Tomas Beaumont", character: "The Stranger"),
        CastMember(id: "demo-7", name: "Iris Calloway", role: .director),
        CastMember(id: "demo-8", name: "Felix Auerbach", role: .writer)
    ]
}
