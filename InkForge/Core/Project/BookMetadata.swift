import Foundation

struct BookMetadata: Codable, Equatable {
    var title: String
    var author: String
    var language: String = "en"
    var cover: String?
    var identifier: String?
}
