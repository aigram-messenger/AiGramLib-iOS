Основной функционал - обработка сообщений ботами.
Проект разбит на подмодули и подпроекты, которые находятся в других репозиториях (основной проект вот тут https://github.com/aigram-messenger/AiGram-iOS.git)

AiGramLib - репо с проектом, в котором находится все, что связано с работой с ботами (структуры, классы, сами боты)
Весь этот функционал используется в TelegramUI (тк, чтобы вынести и UI в отдельные проект/либо, нужно менять области видимости внутри TelegramUI, что приведет к еще большим конфликтам при слиянии оригинальных обновлений телеги).

На текущий момент начата работа по добавлению псевдо бота "праздники".

Классы UI элементов панели с ботами находятся в TelegramUI/Controllers/Chat/Input Nodes/Bots
Классы UI элементов панели деталей о боте находятся в TelegramUI/Controllers/Chat/Bot Details Preview


Структура "архитектуры" в UI:

в чате есть класс, который хранит в себе замыкания на различные действия (типа отправки сообщения, обновления состояния и тдтп) - ChatControllerInteraction.swift
он передается в другие места для быстрого доступа к этим функциям
Сейчас там 5 дополнительных замыканий для обработки сообщений, отображения деталей о боте и экшинов при долгом нажатии, покупке бота

/// messages, userInitiated
let handleMessagesWithBots: ([String]?, Bool) -> Void
let showBotDetails: (ChatBot, @escaping () -> Void) -> Void
let showBotActions: (ChatBot, @escaping () -> Void) -> Void
let buyBot: (ChatBot, @escaping (Bool) -> Void) -> Void
let handleSuggestionTap: (String) -> Void

при нажатии на сообщение, предложенное ботом оно только вставляется в текстовой поле, и потом пользователь может отправить его либо отредактировать

контроллер чата находится в ChatController.swift
в нем есть поля
private var currentMessages: [String]?
private var currentReply: Bool?
var messageToReply: Message? {
    if let messageId = self.presentationInterfaceState.interfaceState.replyMessageId,
        let message = self.chatDisplayNode.historyNode.messageInCurrentHistoryView(messageId) {
        return message
    }
    return nil
}
и методы
private func showBotActions(_ bot: ChatBot, completion: @escaping () -> Void)
private func showBotDetailsAlert(_ bot: ChatBot, completion: @escaping () -> Void)
private func requestHandlingLastMessages(_ messages: [String]?, byUserInitiating: Bool = false)
private func updateText(_ text: String)

прямого доступа к панели с ботами нет, для этого используется команда
self.updateChatPresentationInterfaceState(animated: true, interactive: true, {
    $0.updatedInputMode { current in
        return ChatInputMode.suggestions(responses: responses, expanded: nil, userInitiated: byUserInitiating)
    }
}
по сути, любые изменения, инициированные за панелью и которые должны произойти в панели, сообщаются ей через эту команду

в файле Chat/Interface State/ChatInterfaceInputNodes.swift есть обработка данного изменения
case .suggestions(let responses, _, _):
    if let currentNode = currentNode as? ChatSuggestionsInputNode {
        currentNode.set(botResponses: responses)
        return currentNode
    } else {
        let inputNode = ChatSuggestionsInputNode(account: account, controllerInteraction: controllerInteraction, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings)
        inputNode.interfaceInteraction = interfaceInteraction
        inputNode.set(botResponses: responses)
        return inputNode
    }
    
участок, где обрабатываются изменения сообщений в чате находится в TelegramUI/Components/Chat History Node/ChatHistoryListNode.swift
в методе enqueueHistoryViewTransition(_:)
...
strongSelf.enqueuedHistoryViewTransition = (transition, {
    if let scrolledToIndex = transition.scrolledToIndex {
        if let strongSelf = self {
            strongSelf.scrolledToIndex?(scrolledToIndex)
        }
    }
    let messages = self?.lastMessages.map { $0.text }
    self?.controllerInteraction.handleMessagesWithBots(messages, false)
    
    subscriber.putCompletion()
})

для работы с UI в телеге используется AsyncDisplayKit
но есть мысль использовать для панели компоненты UIKit и просто добавить всю панель внутрь ASNode (ChatInputNode наследника) - потеряется асинхронность отрисовки ui, но при этом можно будет вынести так же и почти весь UI в свой проект