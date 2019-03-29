//
//  PopularSuggestionManager.swift
//  AiGramLib
//
//  Created by Vladislav Sedinkin on 25/03/2019.
//  Copyright © 2019 Ol Corporation. All rights reserved.
//

import Foundation

private struct PopularSuggestionWeight: Codable {
    let suggestionHash: Int
    let tagHash: Int
    var weight: Int
    
    mutating func increaseWeight() {
        weight += 1
    }
    
    static func new(suggestion: String, tag: String) -> PopularSuggestionWeight {
        return .init(
            suggestionHash: suggestion.sdbmhash,
            tagHash: tag.sdbmhash,
            weight: 1
        )
    }
}

private struct PopularBotSuggestions: Codable {
    let botId: AiGramBot.ChatBotId
    private var recent: [PopularSuggestionWeight]
    var mostPopular: PopularSuggestionWeight {
        return recent.max { $0.weight < $1.weight }!
    }
    
    func mostPopular(for tag: String) -> PopularSuggestionWeight? {
        return recent
            .filter { $0.tagHash == tag.sdbmhash }
            .max { $0.weight < $1.weight }
    }
    
    init(botId: AiGramBot.ChatBotId, suggestion: String, tag: String) {
        self.botId = botId
        let recentSuggestion = PopularSuggestionWeight.new(suggestion: suggestion, tag: tag)
        recent = [recentSuggestion]
    }
    
    mutating func addSuggestion(_ suggestion: String, tag: String) {
        let hash = suggestion.sdbmhash
        if let indexOfExitstingSuggestion = recent.firstIndex(where: { $0.suggestionHash == hash }) {
            var existingSuggestion = recent[indexOfExitstingSuggestion]
            existingSuggestion.increaseWeight()
            recent[indexOfExitstingSuggestion] = existingSuggestion
        } else {
            recent.append(
                PopularSuggestionWeight.new(suggestion: suggestion, tag: tag)
            )
        }
    }
}

final class PopularSuggestionManager {
    private var popularSuggestions: [PopularBotSuggestions]
    private let managerQueue: DispatchQueue = .init(label: "com.bot.suggestion.queue")
    
    init() {
        self.popularSuggestions = []
    }
    
    func use(suggestion: String, tag: String, of botId: AiGramBot.ChatBotId) {
        managerQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let indexOfExitstingBot = self.popularSuggestions.firstIndex(where: { $0.botId == botId }) {
                var existingSuggestion = self.popularSuggestions[indexOfExitstingBot]
                existingSuggestion.addSuggestion(suggestion, tag: tag)
                self.popularSuggestions[indexOfExitstingBot] = existingSuggestion
            } else {
                self.popularSuggestions.append(
                    PopularBotSuggestions(botId: botId, suggestion: suggestion, tag: tag)
                )
            }
            
            self.popularSuggestions.sort(by: { $0.mostPopular.weight > $1.mostPopular.weight })
            self.save()
        }
    }
    
    private func save() {
        if let data = try? JSONEncoder().encode(self.popularSuggestions) {
            UserDefaults.standard.set(data, forKey: "suggestions")
        }
    }
    
    func restoreSuggestions() {
        guard
            let data = UserDefaults.standard.data(forKey: "suggestions"),
            let popularSuggestions = try? JSONDecoder().decode([PopularBotSuggestions].self, from: data)
        else {
            return
        }
        
        self.popularSuggestions = popularSuggestions
    }
    
    func getMostPopularBotsMessages(_ handledResults: [ChatBotResult]) -> [String]? {
        guard
            !popularSuggestions.isEmpty,
            !handledResults.isEmpty
        else {
            return nil
        }
        
        typealias SuggestionsData = (mostPopular: PopularSuggestionWeight, suggestion: String)
        
        let result = handledResults
            .flatMap {
                $0.responses.flatMap { botResponse in
                    botResponse.response.map { ($0, botResponse.tag) }
                }
            }
            .compactMap { suggestion, tag -> SuggestionsData? in
                popularSuggestions
                    .compactMap { $0.mostPopular(for: tag) }
                    .first { $0.suggestionHash == suggestion.sdbmhash }
                    .map { ($0, suggestion) }
            }
            .sorted { $0.mostPopular.weight > $1.mostPopular.weight }
            .map { $0.suggestion }
        
        guard !result.isEmpty else {
            return nil
        }
        
        return result
    }
}

extension String {
    var sdbmhash: Int {
        let unicodeScalars = self.unicodeScalars.map { $0.value }
        return unicodeScalars.reduce(0) {
            (Int($1) &+ ($0 << 6) &+ ($0 << 16)).addingReportingOverflow(-$0).partialValue
        }
    }
}
