//
//  ChatBotsManager.swift
//  TelegramUI
//
//  Created by Dmitry Shelonin on 25/12/2018.
//  Copyright © 2018 Telegram. All rights reserved.
//

import Foundation
import UIKit
import FirebaseCore
import FirebaseFunctions

public enum Result<T> {
    case success(T)
    case fail(Error)
}

public final class ChatBotsManager {
    static let shared: ChatBotsManager = .init()
    private(set) public var bots: [ChatBot] = []
    private var loadedBotsFlag: Bool = false
    private(set) public var loadedBotsInStore: [ChatBot] = []
    private var queue: OperationQueue
    private var searchQueue: OperationQueue
    private var lastMessages: [String]?
    private var lastSearchText: String?
    private var storeBotsLoadingStarted: Bool = false
    private var storeBotsLoadingCompletions: [(Result<[ChatBot]>) -> Void] = []
    private let session = URLSession(configuration: .default)
    
    public var autoOpenBots: Bool {
        get { return (UserDefaults.standard.value(forKey: "autoOpenBots") as? Bool) ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoOpenBots")
            UserDefaults.standard.synchronize()
        }
    }
    public var inviteUrl: String {
        return "https://aigram.app/dl"
    }
    public var shareText: String {
        return """
            Привет, я общаюсь здесь с тобой используя нейроботов – помощников для переписок. Скачай AiGram – мессенджер с Искусственным интеллектом и продолжай общаться с пользователями Telegram в новом формате!
            https://aigram.app/dl
            """
    }
    
    private lazy var functions = Functions.functions()
    private var botsDetailsFromBack: [ChatBot.ChatBotId: ChatBotBackDetails] = [:]
    
    private init() {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        searchQueue = OperationQueue()
        searchQueue.maxConcurrentOperationCount = 1
        
        let free = self.freeBots()
        let local = self.localBots()
        self.bots = free + local
        
        self.getTreshovieBots { result in
            self.botsDetailsFromBack = result
        }
        
//        let temp = bots
//        for bot in temp {
//            deleteBot(bot)
//        }
    }
    
    public func botDetails(_ bot: ChatBot) -> ChatBotBackDetails {
        var details: ChatBotBackDetails
        
        if let temp = self.botsDetailsFromBack[bot.name] {
            details = temp
        } else {
            details = ChatBotBackDetails(name: bot.name,
                                         installation: "0",
                                         deletion: "0",
                                         theme: "0",
                                         phrase: "0",
                                         price: "0",
                                         rating: "0",
                                         votings: "0")
        }
        
        return details
    }
    
    public func handleMessages(_ messages: [String], completion: @escaping ([ChatBotResult]) -> Void) {
        lastMessages = messages
        queue.addOperation {
            let localQueue = OperationQueue()
            let lock = NSRecursiveLock()
            var results: [ChatBotResult] = []
            
            for bot in self.bots {
                guard self.isBotEnabled(bot) else { continue }
                localQueue.addOperation {
                    let processor = BotProcessor(bot: bot)
                    let result = processor.process(messages: messages)
                    if !result.responses.isEmpty {
                        lock.lock()
                        results.append(result)
                        lock.unlock()
                    }
                }
            }
            
            localQueue.waitUntilAllOperationsAreFinished()
            DispatchQueue.main.async {
                if messages == self.lastMessages {
                    self.lastMessages = nil
                    results = self.resultsWithAssistantHandling(results: results)
                    completion(results)
                }
            }
        }
    }
    
    private func resultsWithAssistantHandling(results: [ChatBotResult]) -> [ChatBotResult] {
        var results = results
        if let index = results.firstIndex(where: { $0.bot.name == "assistant" }), index > 0 {
            let temp = results.remove(at: index)
            results.insert(temp, at: 0)
        }
        
        return results
    }
    
    public func botsInStore(completion: @escaping (Result<[ChatBot]>) -> Void) {
        if loadedBotsFlag {
            completion(.success(self.loadedBotsInStore))
            return
        }
        storeBotsLoadingCompletions.append(completion)
        guard !storeBotsLoadingStarted else { return }
        self.storeBotsLoadingStarted = true
        DispatchQueue.global().asyncAfter(deadline: .now()) {
            var result: [ChatBot] = []
            
            let bundle = Bundle(for: ChatBotsManager.self)
            let urls = bundle.urls(forResourcesWithExtension: ChatBot.botExtension, subdirectory: "bots") ?? []
            var tempBots: [ChatBot.ChatBotId: ChatBot] = [:]
            var linkedNames: Set<ChatBot.ChatBotId> = Set()
            for url in urls {
                do {
                    let bot = try ChatBot(url: url)
                    guard !bot.isTarget else { continue }
                    tempBots[bot.name] = bot
                    if let nextName = bot.nextBotId {
                        linkedNames.insert(nextName)
                    }
                } catch {
                    print("ERROR INIT BOT \(error)")
                }
            }
            
            var name = Set(tempBots.keys).subtracting(linkedNames).first
            var index = 1
            while let currentName = name {
                if var bot = tempBots[currentName] {
                    bot.index = index
                    result.append(bot)
                    
                    name = bot.nextBotId
                    index += 1
                } else {
                    break
                }
            }
            
            BotsStoreManager.shared.loadProducts(for: result) { [weak self] in
                DispatchQueue.main.async {
                    self?.loadedBotsInStore = result
                    self?.loadedBotsFlag = true
                    self?.storeBotsLoadingCompletions.forEach({ (block) in
                        block(.success(result))
                    })
                    self?.storeBotsLoadingCompletions.removeAll()
                }
            }
        }
    }
    
    public func search(_ text: String, completion: @escaping ([ChatBot]) -> Void) {
        if self.lastSearchText != text {
            self.lastSearchText = nil
            self.searchQueue.cancelAllOperations()
        }
        self.lastSearchText = text
        let block = BlockOperation { [unowned self, text] in
            guard self.lastSearchText == text else { return }
            let result: [ChatBot] = self.bots.filter { $0.isAcceptedWithText(text) }
            DispatchQueue.main.async {
                completion(result)
            }
        }
        self.searchQueue.addOperation(block)
    }
    
    public func copyBot(_ bot: ChatBot) -> Bool {
        guard !bot.tags.contains(String(describing: ChatBotTag.free)) else { return true }
        let fm = FileManager.default
        guard var destinationUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        
        destinationUrl.appendPathComponent("chatbots", isDirectory: true)
        if !((try? destinationUrl.checkResourceIsReachable()) ?? false) {
            do {
                try fm.createDirectory(at: destinationUrl, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return false
            }
        }
        destinationUrl.appendPathComponent("\(bot.fileNameComponents.0).\(bot.fileNameComponents.1)", isDirectory: true)
        if ((try? destinationUrl.checkResourceIsReachable()) ?? false) {
            try? fm.removeItem(at: destinationUrl)
        }
        
        do {
            try fm.copyItem(at: bot.url, to: destinationUrl)
            let newBot = try ChatBot(url: destinationUrl)
            bots.append(newBot)
        } catch {
            return false
        }
        
        return true
    }
    
//    public func deleteBot(_ bot: ChatBot) {
//        let fm = FileManager.default
//        guard var botUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
//        botUrl.appendPathComponent("chatbots", isDirectory: true)
//        botUrl.appendPathComponent("\(bot.fileNameComponents.0).\(bot.fileNameComponents.1)", isDirectory: true)
//        try? fm.removeItem(at: botUrl)
//    }
    
    public func enableBot(_ bot: ChatBot, enabled: Bool, userId: Int32, completion: @escaping () -> Void) {
        var botEnableStates: [ChatBot.ChatBotId: Bool] = (UserDefaults.standard.value(forKey: "EnabledBots") as? [ChatBot.ChatBotId: Bool]) ?? [:]
        botEnableStates[bot.name] = enabled
        UserDefaults.standard.setValue(botEnableStates, forKey: "EnabledBots")
        UserDefaults.standard.synchronize()
        self.sendEnablingBot(bot, enabled: enabled, userId: userId, completion: completion)
    }
    
    public func isBotEnabled(_ bot: ChatBot) -> Bool {
        let botEnableStates: [ChatBot.ChatBotId: Bool] = (UserDefaults.standard.value(forKey: "EnabledBots") as? [ChatBot.ChatBotId: Bool]) ?? [:]
        return botEnableStates[bot.name] ?? true
    }
    
    public func sendFirstStartIfNeeded(userId: Int32) {
        guard UserDefaults.standard.value(forKey: "WasStartedBefore") == nil else { return }
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/installDeleteApp?app_id=telegram_client&type=1&user_id=\(userId)")
        self.session.dataTask(with: url) { [weak self] (data, response, error) in
            print("\(error) \(data) \(response)")
            if error == nil {
                UserDefaults.standard.setValue(true, forKey: "WasStartedBefore")
                UserDefaults.standard.synchronize()
                self?.getTreshovieBots { [weak self] result in
                    DispatchQueue.main.async {
                        self?.botsDetailsFromBack = result
                    }
                }
            }
        }.resume()
    }
    
    public func rateBot(_ bot: ChatBot, rating: Int, userId: Int32, completion: @escaping (Error?) -> Void) {
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/voteBot?user_id=\(userId)&bot_id=\(bot.name)&rating=\(rating)")
        self.session.dataTask(with: url) { [weak self] (_, _, error) in
            if let error = error {
                DispatchQueue.main.async {
                    completion(error)
                }
            } else {
                self?.getTreshovieBots { [weak self] result in
                    DispatchQueue.main.async {
                        self?.botsDetailsFromBack = result
                        completion(nil)
                    }
                }
            }
        }.resume()
    }
    
    func sendEnablingBot(_ bot: ChatBot, enabled: Bool, userId: Int32, completion: @escaping (() -> Void)) {
        let type = enabled ? 1 : 2
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/installDeleteBot?bot_id=\(bot.name)&type=\(type)&user_id=\(userId)")
        self.session.dataTask(with: url) { [weak self] (data, response, error) in
            print("\(error) \(data) \(response)")
            if error == nil {
                self?.getTreshovieBots { [weak self] result in
                    DispatchQueue.main.async {
                        self?.botsDetailsFromBack = result
                        completion()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }.resume()
    }
    
    public func isBotRatedBy(_ userId: Int32, bot: ChatBot, completion: @escaping (ChatBotDetailsRated?) -> Void) {
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/getBotVoting?user_id=\(userId)&bot_id=\(bot.name)")
        self.session.dataTask(with: url) { (data, response, error) in
            print("\(error) \(data) \(response)")
            var result: ChatBotDetailsRated?
            if let data = data {
                let decoder = JSONDecoder()
                do {
                    let temp = try decoder.decode(TempBackDetails<ChatBotDetailsRated>.self, from: data)
                    result = temp.payload.first
                } catch {
                    print("\(error)")
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }.resume()
    }
}

extension ChatBotsManager {
    private var targetBot: ChatBot? {
        //TODO: not implemented
        return nil
    }
    
    private struct TempBackDetails<T: Codable>: Codable {
        let payload: [T]
    }
    
    private func freeBots() -> [ChatBot] {
        let bundle = Bundle(for: ChatBotsManager.self)
        let urls = bundle.urls(forResourcesWithExtension: ChatBot.botExtension, subdirectory: "bots") ?? []
        var result: [ChatBot] = []
        for url in urls {
            do {
                let bot = try ChatBot(url: url)
                guard bot.tags.contains(String(describing: ChatBotTag.free)) else { continue }
                result.append(bot)
            } catch {
                print("ERROR INIT BOT \(error)")
            }
        }
        return result
    }
    
    private func localBots() -> [ChatBot] {
        let fm = FileManager.default
        guard var chatBotsUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var result: [ChatBot] = []
        chatBotsUrl.appendPathComponent("chatbots", isDirectory: true)
        if !((try? chatBotsUrl.checkResourceIsReachable()) ?? false) {
            try? fm.createDirectory(at: chatBotsUrl, withIntermediateDirectories: true, attributes: nil)
        }
        
        print("BOTS LOCAL URL \(chatBotsUrl)")
        let urls = (try? fm.contentsOfDirectory(at: chatBotsUrl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            guard let bot = try? ChatBot(url: url) else { continue }
            result.append(bot)
        }
        return result
    }
    
    private func getTreshovieBots(success: @escaping ([ChatBot.ChatBotId: ChatBotBackDetails]) -> Void) {
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/getBotsInfo")
        let dataTask = self.session.dataTask(with: url) { [weak self] (data, response, error) in
            print("\(error)")
            guard let self = self else { return }
            var result: [ChatBot.ChatBotId: ChatBotBackDetails] = [:]
            var error = error
            if let data = data {
                let decoder = JSONDecoder()
                do {
                    let temp = try decoder.decode(TempBackDetails<ChatBotBackDetails>.self, from: data)
                    for detail in temp.payload {
                        result[detail.name] = detail
                    }
                } catch let err {
                    error = err
                    print("\(err)")
                }
            }
            DispatchQueue.main.async {
                if error != nil {
                    result = self.botsDetailsFromBack
                }
                success(result)
            }
        }
        dataTask.resume()
    }
}
