//
//  BotsStoreManager.swift
//  TelegramUI
//
//  Created by Dmitry Shelonin on 09/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import Foundation
import StoreKit

public final class BotsStoreManager: NSObject {
    public static let shared: BotsStoreManager = .init()
    
    private let prefix = "com.olcorporation.olai.bot."
    private var productsRequest: SKProductsRequest?
    private(set) public var products: [SKProduct] = []
    private var productsCompletion: (() -> Void)?
    private var buyCompletions: [String: (Bool) -> Void] = [:]
    
    public var userId: Int32!
    
    private override init() {
        super.init()
        
        SKPaymentQueue.default().add(self)
    }
    
    public func loadProducts(for bots: [ChatBot], _ completion: @escaping () -> Void) {
        self.productsCompletion = { [weak self] in
            completion()
            self?.productsCompletion = nil
        }
        
        var productIds: [String] = []
        bots.forEach {
            productIds.append(self.idOfBot($0))
        }
        let request = SKProductsRequest(productIdentifiers: Set(productIds))
        request.delegate = self
        self.productsRequest = request
        request.start()
    }
    
    public func buyBot(_ bot: ChatBot, completion: @escaping (Bool) -> Void) {
        if isBotBought(bot) {
            completion(true)
            return
        }
        let id = self.idOfBot(bot)
        guard let product = self.products.first(where: { $0.productIdentifier == id }) else {
            completion(false)
            return
        }
        buyCompletions[id] = completion
        let payment = SKMutablePayment(product: product)
        payment.quantity = 1
        SKPaymentQueue.default().add(payment)
    }
    
    public func isBotBought(_ bot: ChatBot) -> Bool {
        return bot.isLocal
    }
    
    public func botPrice(bot: ChatBot) -> Float {
        let id = self.idOfBot(bot)
        guard let product = self.products.first(where: { $0.productIdentifier == id }) else { return 0 }
        return Float(truncating: product.price)
    }
    
    public func botPriceString(bot: ChatBot, defaultValue: String = "ПОЛУЧИТЬ") -> String {
        let id = self.idOfBot(bot)
        guard let product = self.products.first(where: { $0.productIdentifier == id }) else { return defaultValue }
        let formatter = NumberFormatter()
        formatter.formatterBehavior = .default
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        let price = formatter.string(from: product.price) ?? defaultValue
        return price
    }
}

extension BotsStoreManager: SKPaymentTransactionObserver {
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchasing: break
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)
                guard let nameSeq = transaction.payment.productIdentifier.split(separator: ".").last else { break }
                let name = BotsStoreManager.idsMap[String(nameSeq)] ?? String(nameSeq)
                guard let bot = ChatBotsManager.shared.loadedBotsInStore.first(where: { $0.name == name }) else { break }
                DispatchQueue.global().async { [weak self] in
                    let copied = ChatBotsManager.shared.copyBot(bot)
                    if copied, let self = self {
                        ChatBotsManager.shared.sendEnablingBot(bot, enabled: true, userId: self.userId, completion: { [weak self] in
                            self?.buyCompletions[transaction.payment.productIdentifier]?(copied)
                            self?.buyCompletions.removeValue(forKey: transaction.payment.productIdentifier)
                        })
                    } else {
                        DispatchQueue.main.async { [weak self] in
                            self?.buyCompletions[transaction.payment.productIdentifier]?(copied)
                            self?.buyCompletions.removeValue(forKey: transaction.payment.productIdentifier)
                        }
                    }
                }
            case .failed:
                print("TRANS FAIL \(transaction.error!)")
                SKPaymentQueue.default().finishTransaction(transaction)
                self.buyCompletions[transaction.payment.productIdentifier]?(false)
                self.buyCompletions.removeValue(forKey: transaction.payment.productIdentifier)
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
            case .deferred: break
            }
        }
    }
}

extension BotsStoreManager: SKProductsRequestDelegate {
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.products = response.products
        self.productsCompletion?()
    }
}

extension BotsStoreManager {
    private static let namesMap: [ChatBot.ChatBotId: String] = [
        "celentano": "Celentano",
        "lannister": "tyrion",
        "spongebob": "sponge_bob"
    ]
    
    private static let idsMap: [String: ChatBot.ChatBotId] = [
        "Celentano": "celentano",
        "tyrion": "lannister",
        "sponge_bob": "spongebob"
    ]
    
    private func idOfBot(_ bot: ChatBot) -> String {
        let name = BotsStoreManager.namesMap[bot.name] ?? bot.name
        let result: String = self.prefix + name
        return result
    }
}
