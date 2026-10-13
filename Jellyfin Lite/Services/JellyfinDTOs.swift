import Foundation

struct PublicSystemInfo: Decodable, Sendable {
    let serverName: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case version = "Version"
    }
}

struct AuthResult: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let id: String
        let name: String
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
    }
    let user: User
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
    }
}

struct ItemsResponse: Decodable, Sendable {
    let items: [ItemDTO]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct ItemDTO: Decodable, Sendable {
    struct UserData: Decodable, Sendable {
        let playedPercentage: Double?
        let playbackPositionTicks: Int64?
        enum CodingKeys: String, CodingKey {
            case playedPercentage = "PlayedPercentage"
            case playbackPositionTicks = "PlaybackPositionTicks"
        }
    }

    let id: String
    let name: String?
    let type: String?
    let productionYear: Int?
    let runTimeTicks: Int64?
    let communityRating: Double?
    let officialRating: String?
    let genres: [String]?
    let overview: String?
    let userData: UserData?
    let albumArtist: String?
    let seriesName: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentBackdropItemId: String?
    let parentLogoItemId: String?
    let seriesId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let albumId: String?
    let albumPrimaryImageTag: String?
    let artists: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", productionYear = "ProductionYear"
        case runTimeTicks = "RunTimeTicks", communityRating = "CommunityRating"
        case officialRating = "OfficialRating", genres = "Genres", overview = "Overview"
        case userData = "UserData", albumArtist = "AlbumArtist", seriesName = "SeriesName"
        case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentLogoItemId = "ParentLogoItemId", seriesId = "SeriesId"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
        case albumId = "AlbumId", albumPrimaryImageTag = "AlbumPrimaryImageTag", artists = "Artists"
    }
}

struct CountsDTO: Decodable, Sendable {
    let movieCount: Int?
    let seriesCount: Int?
    let albumCount: Int?
    let bookCount: Int?

    enum CodingKeys: String, CodingKey {
        case movieCount = "MovieCount", seriesCount = "SeriesCount"
        case albumCount = "AlbumCount", bookCount = "BookCount"
    }
}
