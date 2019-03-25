//
//  Entities.swift
//  TelegramUI
//
//  Created by Dmitry Shelonin on 17/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import Foundation
import UIKit

public struct BotResponse: Codable, Equatable {
    public let response: [String]
    public let tag: String
    
    public init(response: [String], tag: String) {
        self.response = response
        self.tag = tag
    }
    
    public init() {
        self.response = []
        self.tag = ""
    }
    
    public static func == (lhs: BotResponse, rhs: BotResponse) -> Bool {
        return lhs.tag == rhs.tag && lhs.response == rhs.response
    }
}

public enum ChatBotError: Error {
    case modelFileNotExists
}

let TargetBotName: String = "target"

public enum ChatBotType: String, Codable, CustomStringConvertible {
    case bot
    case notifier
    case recent
    
    public var description: String {
        return "NeuroBot"
    }
}

public enum ChatBotTag: String, Codable {
    case paid
    case free
    case men
    case women
    case unisex
    case films
    case cartoon
    case known
    case collections
    case great
    
    public func localizedDescription(_ baseLanguageCode: String) -> String {
        let isEnglish = baseLanguageCode == "en"
        
        switch self {
        case .paid: return isEnglish ? "paid" : "платные"
        case .free: return isEnglish ? "free" : "бесплатные"
        case .men: return isEnglish ? "male" : "мужские"
        case .women: return isEnglish ? "female" : "женские"
        case .unisex: return isEnglish ? "female/male" : "женские/мужские"
        case .films: return isEnglish ? "movie characters" : "персонажи фильмов"
        case .cartoon: return isEnglish ? "cartoon characters" : "персонажи мультфильмов"
        case .known: return isEnglish ? "famous" : "известные"
        case .collections: return isEnglish ? "collections" : "коллекции"
        case .great: return isEnglish ? "great" : "великие"
        }
    }
}

private struct ChatBotInfo: Codable {
    let title: String
    let name: AiGramBot.ChatBotId
    let shortDescription: String
    let type: ChatBotType
    let tags: [ChatBotTag]
    let next: AiGramBot.ChatBotId?
    let price: Int?
    let addDate: String
    let updateDate: String
    let developer: String
    let lang: String
}

public struct ChatBotBackDetails: Codable {
    public let name: String
    public let installation: String
    public let deletion: String
    public let theme: String
    public let phrase: String
    public let price: String
    public let rating: String
    public let votings: String
}

public struct ChatBotDetailsRated: Codable {
    public let userId: String
    public let botId: AiGramBot.ChatBotId
    public let rating: String
    
    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case botId = "bot_id"
        case rating
    }
}

public struct BotFileComponents {
    public let name: String
    public let `extension`: String
    
    public var fileName: String {
        return "\(name).\(`extension`)"
    }
}

// MARK: AiGramBot

public protocol AiGramBot {
    typealias ChatBotId = String
    
    var addDate: String { get }
    var developer: String { get }
    var fileNameComponents: BotFileComponents { get }
    var fullDescription: String { get }
    var id: Int { get }
    var isTarget: Bool { get }
    var index: Int { get set }
    var isLocal: Bool { get }
    var name: ChatBotId { get }
    var nextBotId: ChatBotId? { get }
    var price: Int { get }
    var shortDescription: String { get }
    var tags: [ChatBotTag] { get }
    var title: String { get }
    var type: ChatBotType { get }
    var updateDate: String { get }
    var url: URL { get }
    var preview: UIImage { get }
    var icon: UIImage { get }
    var lang: String { get }
    var responses: [BotResponse] { get }
    
    var typeDesciption: String { get }
    var tagsDescriptions: [String] { get }
    
    func toComparable() -> AnyBotComparable
}

extension AiGramBot {
    public var typeDesciption: String {
        return type.description
    }
    
    public var tagsDescriptions: [String] {
        return tags.map { $0.localizedDescription(lang) }
    }
    
    public func isAcceptedWithText(_ text: String) -> Bool {
        let text = text.lowercased()
        guard !text.isEmpty else { return true }
        var result = false
        
        result = result || title.lowercased().contains(text)
        result = result || shortDescription.lowercased().contains(text)
        result = result || fullDescription.lowercased().contains(text)
        
        return result
    }
    
    public func isEqual(_ other: AiGramBot) -> Bool {
        return self.name == other.name
    }
    
    public func isLess(then other: AiGramBot) -> Bool {
        return self.index < other.index
    }
}

// MARK: BotFactory

final class BotFactory {
    static func createBot(with url: URL) throws -> AiGramBot {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url.appendingPathComponent("info.json"))
        let info = try decoder.decode(ChatBotInfo.self, from: data)
        switch info.type {
        case .bot:
            return try ChatBot(url: url, info: info, decoder: decoder)
        case .notifier:
            return try HolidaysBot(url: url, info: info, decoder: decoder)
        case .recent:
            fatalError("Cannot create bot with type `recent`")
        }
    }
    
    private init () {}
}

// MARK: Notifier

public struct HolidaysBot: AiGramBot {
    private enum Error: Swift.Error {
        case indefiendHolidayDate
    }
    
    public enum HolidayType: String {
        case d14_02 = "14.02"
        case d23_02 = "23.02"
        case d08_03 = "08.03"
        case d01_04 = "01.04"
        case d12_04 = "12.04"
        
        fileprivate init(stringDate: String) throws {
            switch stringDate {
            case HolidayType.d14_02.rawValue:
                self = .d14_02
            case HolidayType.d23_02.rawValue:
                self = .d23_02
            case HolidayType.d08_03.rawValue:
                self = .d08_03
            case HolidayType.d01_04.rawValue:
                self = .d01_04
            case HolidayType.d12_04.rawValue:
                self = .d12_04
            default:
                throw Error.indefiendHolidayDate
            }
        }
        
        fileprivate func icon(in url: URL) -> UIImage? {
            return UIImage(
                in: url.appendingPathComponent("icon-\(rawValue)"),
                name: "icon",
                ext: "png"
            )
        }
    }
    
    private let info: ChatBotInfo
    
    public let fileNameComponents: BotFileComponents
    public let url: URL
    public var addDate: String { return info.addDate }
    public var developer: String { return info.developer }
    public var fullDescription: String { return shortDescription }
    public var id: Int { return name.hashValue }
    public var index: Int = 0
    public var isTarget: Bool { return name == TargetBotName }
    public var lang: String { return info.lang }
    public var name: ChatBotId { return info.name }
    public var nextBotId: ChatBotId? { return info.next }
    public var price: Int { return info.price ?? 0 }
    public var shortDescription: String { return info.shortDescription }
    public var tags: [ChatBotTag] { return info.tags }
    public var title: String { return info.title }
    public var type: ChatBotType { return info.type }
    public var updateDate: String { return info.updateDate }
    public var isLocal: Bool { return true }
    
    public let holidayTypes: [HolidayType]
    public let preview: UIImage
    public let icon: UIImage
    public var activeHoliday: HolidayType?
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM"
        return df
    }()
    
    public let responses: [BotResponse]
    
    public init(url: URL) throws {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url.appendingPathComponent("info.json"))
        let info = try decoder.decode(ChatBotInfo.self, from: data)
        
        try self.init(url: url, info: info, decoder: decoder)
    }
    
    fileprivate init(
        url: URL,
        info: ChatBotInfo,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        // TODO: Need optimization
        
        self.url = url
        self.info = info
        
        fileNameComponents = BotFileComponents(
            name: url.deletingPathExtension().lastPathComponent,
            extension: url.pathExtension
        )
        
        let data = try Data(contentsOf: url.appendingPathComponent("response_\(fileNameComponents.name).json"))
        responses = try decoder.decode(Swift.type(of: responses), from: data)
        
        holidayTypes = try responses.map { try HolidayType(stringDate: $0.tag) }
        let currentTag = HolidaysBot.dateFormatter.string(from: Date())
        activeHoliday = holidayTypes.first(where: { $0.rawValue == currentTag })
        icon = activeHoliday?.icon(in: url) ?? UIImage()
        preview = UIImage(in: url, name: "preview", ext: "png") ?? UIImage()
    }
    
    public func toComparable() -> AnyBotComparable {
        return AnyBotComparable(self)
    }
}

extension HolidaysBot: Comparable {
    public static func == (lhs: HolidaysBot, rhs: HolidaysBot) -> Bool {
        return lhs.name == rhs.name
    }
    
    public static func < (lhs: HolidaysBot, rhs: HolidaysBot) -> Bool {
        return lhs.index < rhs.index
    }
}

// MARK: Bot

public struct ChatBot: AiGramBot {
    private let info: ChatBotInfo
    
    public let fileNameComponents: BotFileComponents
    public let url: URL
    public var addDate: String { return info.addDate }
    public var developer: String { return info.developer }
    public var fullDescription: String { return shortDescription }
    public var id: Int { return name.hashValue }
    public var index: Int = 0
    public var isTarget: Bool { return name == TargetBotName }
    public var lang: String { return info.lang }
    public var name: ChatBotId { return info.name }
    public var nextBotId: ChatBotId? { return info.next }
    public var price: Int { return info.price ?? 0 }
    public var shortDescription: String { return info.shortDescription }
    public var tags: [ChatBotTag] { return info.tags }
    public var title: String { return info.title }
    public var type: ChatBotType { return info.type }
    public var updateDate: String { return info.updateDate }
    
    public let words: [String]
    public let responses: [BotResponse]
    
    public let icon: UIImage
    public let modelURL: URL
    public let preview: UIImage
    
    public var isLocal: Bool {
        guard
            !self.tags.contains(.free)
        else {
            return true
        }
        let fm = FileManager.default
        guard var destinationUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        destinationUrl.appendPathComponent("chatbots/\(info.lang)", isDirectory: true)
        destinationUrl.appendPathComponent(fileNameComponents.fileName, isDirectory: true)
        let result = (try? destinationUrl.checkResourceIsReachable()) ?? false
        return result
    }
    
    public init(url: URL) throws {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: url.appendingPathComponent("info.json"))
        let info = try decoder.decode(ChatBotInfo.self, from: data)
        
        try self.init(url: url, info: info, decoder: decoder)
    }
    
    fileprivate init(
        url: URL,
        info: ChatBotInfo,
        decoder: JSONDecoder = JSONDecoder()
    ) throws {
        self.url = url
        self.info = info
        fileNameComponents = BotFileComponents(
            name: url.deletingPathExtension().lastPathComponent,
            extension: url.pathExtension
        )
        
        modelURL = url.appendingPathComponent("converted_model.tflite")
        if !(try modelURL.checkResourceIsReachable()) { throw ChatBotError.modelFileNotExists }
        
        var data = try Data(contentsOf: url.appendingPathComponent("words_\(fileNameComponents.name).json"))
        words = try decoder.decode(Swift.type(of: words), from: data)
        
        data = try Data(contentsOf: url.appendingPathComponent("response_\(fileNameComponents.name).json"))
        responses = try decoder.decode(Swift.type(of: responses), from: data)
        
        icon = UIImage(in: url, name: "icon", ext: "png") ?? UIImage()
        preview = UIImage(in: url, name: "preview", ext: "png") ?? UIImage()
    }
    
    public func toComparable() -> AnyBotComparable {
        return AnyBotComparable(self)
    }
}

extension ChatBot: Comparable {
    public static func == (lhs: ChatBot, rhs: ChatBot) -> Bool {
        return lhs.name == rhs.name
    }
    
    public static func < (lhs: ChatBot, rhs: ChatBot) -> Bool {
        return lhs.index < rhs.index
    }
}

struct PopularSuggestionsBot: AiGramBot {
    var addDate: String = ""
    var developer: String = ""
    var fileNameComponents: BotFileComponents = .init(name: "", extension: "")
    var fullDescription: String = ""
    var id: Int = -1
    var isTarget: Bool = false
    var index: Int = -1
    var isLocal: Bool = true
    var name: ChatBotId = ""
    var nextBotId: ChatBotId?
    var price: Int = 0
    var shortDescription: String = ""
    var tags: [ChatBotTag] = []
    var title: String = ""
    var type: ChatBotType = .recent
    var updateDate: String = ""
    var url: URL = URL(fileURLWithPath: "")
    var preview: UIImage = .init()
    let icon: UIImage = .init()
    var lang: String = ""
    var responses: [BotResponse] = []
    
    init(language: String) {
        self.lang = language
        self.title = language == "ru" ? "Недавние" : "Recent"
    }
    
    func toComparable() -> AnyBotComparable {
        return AnyBotComparable(self)
    }
}

extension PopularSuggestionsBot: Comparable {
    public static func == (lhs: PopularSuggestionsBot, rhs: PopularSuggestionsBot) -> Bool {
        return lhs.name == rhs.name
    }
    
    public static func < (lhs: PopularSuggestionsBot, rhs: PopularSuggestionsBot) -> Bool {
        return lhs.index < rhs.index
    }
}

public struct ChatBotResult {
    public let bot: AiGramBot
    public let responses: [BotResponse]
}

extension ChatBotResult: Equatable {
    public static func == (lhs: ChatBotResult, rhs: ChatBotResult) -> Bool {
        return lhs.bot.isEqual(rhs.bot) &&
            lhs.responses == rhs.responses
    }
}

extension Comparable { typealias ComparableSelf = Self }
public struct AnyBotComparable: Comparable {
    public let value: AiGramBot
    let isEqual: (AnyBotComparable) -> Bool
    let isLess: (AnyBotComparable) -> Bool
    init<T: Comparable>(_ value: T) where T: AiGramBot {
        self.value = value
        self.isEqual = { rhs in
            guard let other = rhs.value as? T.ComparableSelf else {
                return false
            }
            return value == other
        }
        self.isLess = { rhs in
            guard let other = rhs.value as? T.ComparableSelf else {
                return false
            }
            return value < other
        }
    }
    
    public static func < (lhs: AnyBotComparable, rhs: AnyBotComparable) -> Bool {
        return lhs.isLess(rhs)
    }
    public static func == (lhs: AnyBotComparable, rhs: AnyBotComparable) -> Bool {
        return lhs.isEqual(rhs)
    }
}
