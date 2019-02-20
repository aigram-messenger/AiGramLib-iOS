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
    let response: [String]
    let tag: String
    
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
    
    public var description: String {
        return "NeuroBot"
    }
}

public enum ChatBotTag: String, Codable, CustomStringConvertible {
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
    
    public var description: String {
        switch self {
        case .paid: return "платные"
        case .free: return "бесплатные"
        case .men: return "мужские"
        case .women: return "женские"
        case .unisex: return "женские/мужские"
        case .films: return "персонажи фильмов"
        case .cartoon: return "персонажи мультфильмов"
        case .known: return "известные"
        case .collections: return "коллекции"
        case .great: return "великие"
        }
    }
}

private struct ChatBotInfo: Codable {
    let title: String
    let name: ChatBot.ChatBotId
    let shortDescription: String
    let type: ChatBotType
    let tags: [ChatBotTag]
    let next: ChatBot.ChatBotId?
    let price: Int?
    let addDate: String
    let updateDate: String
    let developer: String
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
    let userId: String
    let botId: ChatBot.ChatBotId
    let rating: String
    
    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case botId = "bot_id"
        case rating
    }
}

public struct ChatBot {
    public typealias ChatBotId = String
    static let botExtension: String = "chatbot"
    
    private let info: ChatBotInfo
    
    public let url: URL
    public let fileNameComponents: (String, String)
    
    public var id: Int { return name.hashValue }
    public var title: String { return info.title }
    public var name: ChatBotId { return info.name }
    public var shortDescription: String { return info.shortDescription }
    public var type: String { return String(describing: info.type) }
    public var isTarget: Bool { return name == TargetBotName }
    public var fullDescription: String { return shortDescription }
    public var tags: [String] { return info.tags.map { String(describing: $0) } }
    public var index: Int = 0
    public var nextBotId: ChatBotId? { return info.next }
    public var price: Int { return info.price ?? 0 }
    public var addDate: String { return info.addDate }
    public var updateDate: String { return info.updateDate }
    public var developer: String { return info.developer }
    
    public let words: [String]
    public let responses: [BotResponse]
    
    public let modelURL: URL
    public let icon: UIImage
    public let preview: UIImage
    
    public var isLocal: Bool {
        guard !self.tags.contains(String(describing: ChatBotTag.free)) else { return true }
        let fm = FileManager.default
        guard var destinationUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        destinationUrl.appendPathComponent("chatbots", isDirectory: true)
        destinationUrl.appendPathComponent("\(fileNameComponents.0).\(fileNameComponents.1)", isDirectory: true)
        let result = (try? destinationUrl.checkResourceIsReachable()) ?? false
        return result
    }
    
    public init(url: URL) throws {
        do {
            self.url = url
            fileNameComponents = (url.deletingPathExtension().lastPathComponent, url.pathExtension)

            let decoder = JSONDecoder()
            var data = try Data(contentsOf: url.appendingPathComponent("info.json"))
            info = try decoder.decode(Swift.type(of: info), from: data)

            modelURL = url.appendingPathComponent("converted_model.tflite")
            if !(try modelURL.checkResourceIsReachable()) { throw ChatBotError.modelFileNotExists }

            data = try Data(contentsOf: url.appendingPathComponent("words_\(fileNameComponents.0).json"))
            words = try decoder.decode(Swift.type(of: words), from: data)

            data = try Data(contentsOf: url.appendingPathComponent("response_\(fileNameComponents.0).json"))
            responses = try decoder.decode(Swift.type(of: responses), from: data)

            icon = UIImage(in: url, name: "icon", ext: "png") ?? UIImage()
            preview = UIImage(in: url, name: "preview", ext: "png") ?? UIImage()
        } catch {
            print("CREATE BOT ERROR \(error)")
            throw error
        }
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
}

extension ChatBot: Equatable {
    public static func == (lhs: ChatBot, rhs: ChatBot) -> Bool {
        return lhs.name == rhs.name
    }
}

extension ChatBot: Comparable {
    public static func < (lhs: ChatBot, rhs: ChatBot) -> Bool {
        return lhs.index < rhs.index
    }
}

extension ChatBot: Identifiable {
    public var stableId: ChatBotId { return self.name }
}

public struct ChatBotResult {
    public let bot: ChatBot
    public let responses: [BotResponse]
}

extension ChatBotResult: Equatable {
    public static func == (lhs: ChatBotResult, rhs: ChatBotResult) -> Bool {
        return lhs.bot == rhs.bot && lhs.responses == rhs.responses
    }
}
