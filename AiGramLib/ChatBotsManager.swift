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
    public static let shared: ChatBotsManager = .init()
    private(set) public var bots: [AiGramBot] = []
    private var loadedBotsFlag: Bool = false
    private(set) public var loadedBotsInStore: [AiGramBot] = []
    private var queue: OperationQueue
    private var searchQueue: OperationQueue
    private var lastMessages: [String]?
    private var lastSearchText: String?
    private var storeBotsLoadingStarted: Bool = false
    private var storeBotsLoadingCompletions: [(Result<[AiGramBot]>) -> Void] = []
    private let session = URLSession(configuration: .default)
    private var baseLanguageCode: String = ""
    private let popularSuggestionsManager: PopularSuggestionManager = {
        let manager = PopularSuggestionManager()
        manager.restoreSuggestions()
        
        return manager
    }()
    
    public func updateLanguageCodeAndLoadBots(_ code: String) {
        queue.addOperation { [weak self] in
            guard let self = self else {
                return
            }
            
            if self.baseLanguageCode != code {
                self.baseLanguageCode = code == "ru" || code == "en" ? code : "ru"
                self.reloadBots()
            }
        }
    }
    
    private func reloadBots() {
        self.loadedBotsFlag = false
        self.storeBotsLoadingStarted = false
        self.botsInStore(completion: { _ in })
        self.setFreeAndLocalBots()
    }
    
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
    private var botUrls: [URL] {
        let bundle = Bundle(for: ChatBotsManager.self)
        return bundle.urls(
            // TODO: Возможно нужно будет использовать разные расширения для разных типов ботов в дальнейшем
            forResourcesWithExtension: "chatbot",
            subdirectory: "bots/\(self.baseLanguageCode)"
        ) ?? []
    }
    
    private lazy var functions = Functions.functions()
    private var botsDetailsFromBack: [AiGramBot.ChatBotId: ChatBotBackDetails] = [:]
    
    private init() {
        FirebaseApp.configure()

        queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        
        searchQueue = OperationQueue()
        searchQueue.maxConcurrentOperationCount = 1
        
        self.getTreshovieBots { result in
            self.botsDetailsFromBack = result
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: queue,
            using: { [weak self] _ in
                self?.checkOldBotCongratulations()
                self?.reloadBots()
            }
        )
//        let temp = bots
//        for bot in temp {
//            deleteBot(bot)
//        }
    }
    
    private func setFreeAndLocalBots() {
        let free = self.freeBots()
        let local = self.localBots()
        self.bots = free + local
    }
    
    public func botDetails(_ bot: AiGramBot) -> ChatBotBackDetails {
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
    
    public typealias UniquePeerId = Int64
    private let congratulationKey: String = "congratulation-"
    
    private func createCongKey(for peerId: UniquePeerId) -> String {
        return "\(congratulationKey)\(peerId)"
    }
    
    public func checkOldBotCongratulations() {
        let currentDate = Date()
        UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.contains(congratulationKey) }
            .filter { ($0.value as? Date) != currentDate }
            .forEach {
                print("Congratulation mark will be removed. \($0.key)")
                UserDefaults.standard.removeObject(forKey: $0.key)
        }
    }
    
    public func markAsCongratulatedPeer(at id: UniquePeerId) {
        UserDefaults.standard.set(
            Date(),
            forKey: createCongKey(for: id)
        )
    }
    
    public func isHolidaysBot(_ id: AiGramBot.ChatBotId) -> Bool {
        return id == "holidays"
    }
    
    public func use(suggestion: String, tag: String, of botId: AiGramBot.ChatBotId) {
        popularSuggestionsManager.use(suggestion: suggestion, tag: tag, of: botId)
    }
    
    private func canUserSendCongratulations(_ peerId: UniquePeerId) -> Bool {
        let userDefaults = UserDefaults.standard
        let key = createCongKey(for: peerId)
        guard
            let congDate = userDefaults.value(forKey: key) as? Date
        else {
            return true
        }
        
        let calendar = Calendar.current
        let congratulationStartOfDay = calendar.startOfDay(for: congDate)
        let currentStartOfDate = calendar.startOfDay(for: Date())
        if congratulationStartOfDay != currentStartOfDate {
            userDefaults.removeObject(forKey: key)
            return true
        }
        
        return false
    }
    
    public func handleMessages(
        _ messages: [String],
        of peerId: UniquePeerId?,
        completion: @escaping ([ChatBotResult]) -> Void
    ) {
        lastMessages = messages
        queue.addOperation { [weak self] in
            guard let self = self else { return }

            let localQueue = OperationQueue()
            localQueue.qualityOfService = .userInteractive
            
            let lock = NSRecursiveLock()
            var results: [ChatBotResult] = []
            
            for bot in self.bots {
                guard self.isBotEnabled(bot) else { continue }
                if bot is HolidaysBot && peerId != nil && !self.canUserSendCongratulations(peerId!) {
                    continue
                }
                
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
            
            results = self.resultsWithAssistantHandling(results: results)
            results = self.resultsWithHolidaysHandling(results: results)
            
            self.popularSuggestionsManager.getMostPopularBotsMessages(results).map {
                let popular = ChatBotResult(
                    bot: PopularSuggestionsBot(language: self.baseLanguageCode),
                    responses: $0.map { BotResponse(response: [$0], tag: "") }
                )
                results.insert(popular, at: 0)
            }
            
            DispatchQueue.main.async {
                if messages == self.lastMessages {
                    self.lastMessages = nil
                    completion(results)
                }
            }
        }
    }
    
    private func resultsWithAssistantHandling(results: [ChatBotResult]) -> [ChatBotResult] {
        return self.results(results, withHandlingBotName: "assistant")
    }
    
    private func resultsWithHolidaysHandling(results: [ChatBotResult]) -> [ChatBotResult] {
        return self.results(results, withHandlingBotName: "holidays")
    }
    
    private func results(_ results: [ChatBotResult], withHandlingBotName name: String) -> [ChatBotResult] {
        var results = results
        if let index = results.firstIndex(where: { $0.bot.name == name }), index > 0 {
            let temp = results.remove(at: index)
            results.insert(temp, at: 0)
        }
        
        return results
    }
    
    public func botsInStore(completion: @escaping (Result<[AiGramBot]>) -> Void) {
        guard !baseLanguageCode.isEmpty else {
            print("Please, set language code before")
            return
        }
        if loadedBotsFlag {
            completion(.success(self.loadedBotsInStore))
            return
        }
        storeBotsLoadingCompletions.append(completion)
        guard !storeBotsLoadingStarted else { return }
        self.storeBotsLoadingStarted = true
        DispatchQueue.global().asyncAfter(deadline: .now()) { [weak self] in
            guard let self = self else { return }
            
            var result: [AiGramBot] = []
            var tempBots: [AiGramBot.ChatBotId: AiGramBot] = [:]
            var linkedNames: Set<AiGramBot.ChatBotId> = Set()
            for url in self.botUrls {
                do {
                    let bot = try BotFactory.createBot(with: url)
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
                switch $0 {
                case .success:
                    DispatchQueue.main.async {
                        self?.loadedBotsInStore = result
                        self?.loadedBotsFlag = true
                        self?.storeBotsLoadingCompletions.forEach({ (block) in
                            block(.success(result))
                        })
                        self?.storeBotsLoadingCompletions.removeAll()
                    }
                case .fail:
                    self?.storeBotsLoadingStarted = false
                }
                
            }
        }
    }
    
    public func search(_ text: String, completion: @escaping ([AiGramBot]) -> Void) {
        if self.lastSearchText != text {
            self.lastSearchText = nil
            self.searchQueue.cancelAllOperations()
        }
        self.lastSearchText = text
        let block = BlockOperation { [unowned self, text] in
            guard self.lastSearchText == text else { return }
            let result: [AiGramBot] = self.bots.filter { $0.isAcceptedWithText(text) }
            DispatchQueue.main.async {
                completion(result)
            }
        }
        self.searchQueue.addOperation(block)
    }
    
    private var localBotsRepo: URL? {
        guard
            var destinationUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        
        destinationUrl.appendPathComponent("chatbots/\(baseLanguageCode)", isDirectory: true)
        return destinationUrl
    }
    
    public func copyBot(_ bot: AiGramBot) -> Bool {
        guard !isFreeBot(bot) else { return true }
        let fm = FileManager.default
        guard var destinationUrl = localBotsRepo else { return false }
        
        if !((try? destinationUrl.checkResourceIsReachable()) ?? false) {
            do {
                try fm.createDirectory(at: destinationUrl, withIntermediateDirectories: true, attributes: nil)
            } catch {
                return false
            }
        }
        destinationUrl.appendPathComponent(bot.fileNameComponents.fileName, isDirectory: true)
        if ((try? destinationUrl.checkResourceIsReachable()) ?? false) {
            try? fm.removeItem(at: destinationUrl)
        }
        
        do {
            try fm.copyItem(at: bot.url, to: destinationUrl)
            let newBot = try BotFactory.createBot(with: destinationUrl)
            DispatchQueue.main.async {
                if self.bots.contains(where: { $0.isEqual(newBot) }) { return }
                self.bots.append(newBot)
            }
        } catch {
            return false
        }
        
        return true
    }
    
//    public func deleteBot(_ bot: AiGramBot) {
//        let fm = FileManager.default
//        guard var botUrl = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
//        botUrl.appendPathComponent("chatbots", isDirectory: true)
//        botUrl.appendPathComponent("\(bot.fileNameComponents.0).\(bot.fileNameComponents.1)", isDirectory: true)
//        try? fm.removeItem(at: botUrl)
//    }
    
    public func enableBot(_ bot: AiGramBot, enabled: Bool, userId: Int32, completion: @escaping () -> Void) {
        var botEnableStates: [AiGramBot.ChatBotId: Bool] = (UserDefaults.standard.value(forKey: "EnabledBots") as? [AiGramBot.ChatBotId: Bool]) ?? [:]
        botEnableStates[bot.name] = enabled
        UserDefaults.standard.setValue(botEnableStates, forKey: "EnabledBots")
        UserDefaults.standard.synchronize()
        self.sendEnablingBot(bot, enabled: enabled, userId: userId, completion: completion)
    }
    
    public func isBotEnabled(_ bot: AiGramBot) -> Bool {
        let botEnableStates: [AiGramBot.ChatBotId: Bool] = (UserDefaults.standard.value(forKey: "EnabledBots") as? [AiGramBot.ChatBotId: Bool]) ?? [:]
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
    
    public func rateBot(_ bot: AiGramBot, rating: Int, userId: Int32, completion: @escaping (Error?) -> Void) {
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
    
    func sendEnablingBot(_ bot: AiGramBot, enabled: Bool, userId: Int32, completion: @escaping (() -> Void)) {
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
    
    public func isBotRatedBy(_ userId: Int32, bot: AiGramBot, completion: @escaping (ChatBotDetailsRated?) -> Void) {
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
    private var targetBot: AiGramBot? {
        //TODO: not implemented
        return nil
    }
    
    private struct TempBackDetails<T: Codable>: Codable {
        let payload: [T]
    }
    
    private func freeBots() -> [AiGramBot] {
        guard !baseLanguageCode.isEmpty else {
            print("Please, set language code before")
            return []
        }
        var result: [AiGramBot] = []
        for url in botUrls {
            do {
                let bot = try BotFactory.createBot(with: url)
                guard isFreeBot(bot) else { continue }
                result.append(bot)
            } catch {
                print("ERROR INIT BOT \(error)")
            }
        }
        return result
    }
    
    private func localBots() -> [AiGramBot] {
        let fm = FileManager.default
        guard let chatBotsUrl = localBotsRepo else { return [] }
        var result: [AiGramBot] = []
        if !((try? chatBotsUrl.checkResourceIsReachable()) ?? false) {
            try? fm.createDirectory(at: chatBotsUrl, withIntermediateDirectories: true, attributes: nil)
        }
        
        print("BOTS LOCAL URL \(chatBotsUrl)")
        let urls = (try? fm.contentsOfDirectory(at: chatBotsUrl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            guard let bot = try? BotFactory.createBot(with: url), !isFreeBot(bot) else { continue }
            result.append(bot)
        }
        return result
    }
    
    private func isFreeBot(_ bot: AiGramBot) -> Bool {
        return bot.tags.contains(.free)
    }
    
    private func getTreshovieBots(success: @escaping ([AiGramBot.ChatBotId: ChatBotBackDetails]) -> Void) {
        let url: URL! = URL(string: "https://us-central1-api-7231730271161646241-853730.cloudfunctions.net/getBotsInfo")
        let dataTask = self.session.dataTask(with: url) { [weak self] (data, response, error) in
            guard let self = self else { return }
            var result: [AiGramBot.ChatBotId: ChatBotBackDetails] = [:]
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
