//
//  BotProcessor.swift
//  TelegramUI
//
//  Created by Dmitry Shelonin on 27/12/2018.
//  Copyright © 2018 Telegram. All rights reserved.
//

import Foundation
import FirebaseCore
import FirebaseMLModelInterpreter

private class InterpreterOperation: Operation {
    private let interpreter: ModelInterpreter
    private let lock: NSCondition = .init()
    private let bot: ChatBot
    private let ioOptions = ModelInputOutputOptions()
    private let inputs = ModelInputs()
    private let wordsToProcess: [String]
    
    var completion: (([BotResponse]) -> Void)?
    
    init(wordsToProcess: [String], interpreter: ModelInterpreter, bot: ChatBot) {
        self.wordsToProcess = wordsToProcess
        self.interpreter = interpreter
        self.bot = bot
        
        super.init()
        
        do {
            try ioOptions.setInputFormat(index: 0, type: .float32, dimensions: [NSNumber(value: bot.words.count)])
            try ioOptions.setOutputFormat(index: 0, type: .float32, dimensions: [1, NSNumber(value: bot.responses.count)])
        } catch let error as NSError {
            print("Failed to set input or output format with error: \(error.localizedDescription)")
        }
    }
    
    override func main() {
        let inputValues = prepareInput(wordsToProcess)
        try? inputs.addInput(inputValues)
        
        interpreter.run(inputs: inputs, options: ioOptions) { [lock, completion] (outputs, error) in
            defer {
                lock.lock()
                lock.signal()
                lock.unlock()
            }
            guard let outputs = outputs else { return }
            do {
                let firstOutput = (try outputs.output(index: 0)) as? [Any] ?? []
                let outputs = firstOutput[0] as? [Float32] ?? []
                var responses: [BotResponse] = []
                for i in 0..<outputs.count where outputs[i] >= 0.9 {
                    responses.append(contentsOf: self.constructResponses(with: self.bot.responses[i]))
                }
                completion?(responses)
            } catch {}
        }
        
        lock.lock()
        lock.wait()
        lock.unlock()
    }
    
    private func prepareInput(_ words: [String]) -> [Float32] {
        var result: [Float32] = Array(repeating: 0, count: bot.words.count)
        let wordsSet = Set(words)
        
        for index in 0..<bot.words.count where wordsSet.contains(bot.words[index]) {
            result[index] = 1
        }
        
        return result
    }
    
    private func constructResponses(with response: BotResponse) -> [BotResponse] {
        var result: [BotResponse] = []
        
        for string in response.response {
            var temp = BotResponse(response: [string], tag: response.tag)
            result.append(temp)
        }
        
        return result
    }
}

public final class BotProcessor {
    public let bot: ChatBot
    private let modelManager: ModelManager = .modelManager()
    
    public init(bot: ChatBot) {
        self.bot = bot
    }
    
    deinit {
    }
}

extension BotProcessor {
    /// Synchronous call
    public func process(messages: [String]) -> ChatBotResult {
        var operations: [Operation] = []
        let queue = OperationQueue()
        let lock = NSRecursiveLock()
        var responses: [BotResponse] = []
        let interpreter = initInterpreter()
        for message in messages {
            let words = self.words(of: message)
            
            let operation = InterpreterOperation(wordsToProcess: words, interpreter: interpreter, bot: bot)
            operation.completion = { results in
                lock.lock()
                responses.append(contentsOf: results)
                lock.unlock()
            }
            operations.append(operation)
        }
        queue.addOperations(operations, waitUntilFinished: true)
        let botResult = ChatBotResult(bot: self.bot, responses: responses)
        return botResult
    }
}

extension BotProcessor {
    private func words(of message: String) -> [String] {
        let tagger = NSLinguisticTagger(tagSchemes: [.lemma], options: 0)
        tagger.string = message
        let range = NSRange(location: 0, length: message.count)
        let options: NSLinguisticTagger.Options = [.omitPunctuation, .omitWhitespace]
        var words: [String] = []
        tagger.enumerateTags(in: range, scheme: .lemma, options: options) { (tag, tokenRange, sentenceRange, stop) in
            let word = (message as NSString).substring(with: tokenRange)
            words.append(word.lowercased())
        }
        return words
    }
    
    private func initInterpreter() -> ModelInterpreter {
        let localModelSource = LocalModelSource(modelName: bot.name, path: bot.modelURL.path)
        modelManager.register(localModelSource)
        let options = ModelOptions(cloudModelName: nil, localModelName: localModelSource.modelName)
        let interpreter = ModelInterpreter.modelInterpreter(options: options)
        return interpreter
    }
}
