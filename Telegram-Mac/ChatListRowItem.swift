//
//  TGDialogRowItem.swift
//  Telegram-Mac
//
//  Created by keepcoder on 07/09/16.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import DateUtils
import SwiftSignalKit
import InAppSettings

enum ChatListPinnedType {
    case some
    case last
    case none
    case ad(EngineChatList.AdditionalItem)
}


final class SelectChatListItemPresentation : Equatable {
    let selected:Set<ChatLocation>
    static func ==(lhs:SelectChatListItemPresentation, rhs:SelectChatListItemPresentation) -> Bool {
        return lhs.selected == rhs.selected
    }
    
    init(_ selected:Set<ChatLocation> = Set()) {
        self.selected = selected
    }
    
    func deselect(chatLocation:ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        let _ = chatLocations.remove(chatLocation)
        return SelectChatListItemPresentation(chatLocations)
    }
    
    func withToggledSelected(_ chatLocation: ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        if chatLocations.contains(chatLocation) {
            let _ = chatLocations.remove(chatLocation)
        } else {
            chatLocations.insert(chatLocation)
        }
        return SelectChatListItemPresentation(chatLocations)
    }
    
}

final class SelectChatListInteraction : InterfaceObserver {
    private(set) var presentation:SelectChatListItemPresentation = SelectChatListItemPresentation()
    
    func update(animated:Bool = true, _ f:(SelectChatListItemPresentation)->SelectChatListItemPresentation)->Void {
        let oldValue = self.presentation
        presentation = f(presentation)
        if oldValue != presentation {
            notifyObservers(value: presentation, oldValue:oldValue, animated:animated)
        }
    }
    
}

enum ChatListRowState : Equatable {
    case plain
    case deletable(onRemove:(ChatLocation)->Void, deletable:Bool)
    
    static func ==(lhs: ChatListRowState, rhs: ChatListRowState) -> Bool {
        switch lhs {
        case .plain:
            if case .plain = rhs {
                return true
            } else {
                return false
            }
        case .deletable(_, let deletable):
            if case .deletable(_, deletable) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}


class ChatListRowItem: TableRowItem {

    struct Badge {
        let dynamicValue: DynamicCounterTextView.Value
        let backgroundColor: NSColor
        let size: NSSize
        init(dynamicValue: DynamicCounterTextView.Value, backgroundColor: NSColor, size: NSSize) {
            self.dynamicValue = dynamicValue
            self.backgroundColor = backgroundColor
            var mapped = NSMakeSize(max(CGFloat(dynamicValue.values.count) * 10 - 10 + 7, size.width + 8), size.height + 7)
            mapped = NSMakeSize(max(mapped.height,mapped.width), mapped.height)
            self.size = mapped
        }
    }
        
    private var messages:[Message]
    var message: Message? {
        return messages.first
    }
    
    let context: AccountContext
    let peer:Peer?
    let renderedPeer:EngineRenderedPeer?
    let groupId: EngineChatList.Group
    let forumTopicData: EngineChatList.ForumTopicData?
    let forumTopicItems:[EngineChatList.ForumTopicData]
    var hasForumIcon: Bool {
        if chatNameLayout != nil, forumTopicNameLayout != nil {
            if forumTopicData != nil {
                return true
            } else if let peer = peer, peer.isForum, titleMode == .forumInfo, case .topic = mode {
                return true
            }
        }
        return false
    }
    
    let chatListIndex:ChatListIndex?
    var peerId:PeerId? {
        return renderedPeer?.peerId
    }
    
    let photo: AvatarNodeState
    
    var isGroup: Bool {
        return groupId != .root
    }
    
    
    override var stableId: AnyHashable {
        switch _stableId {
        case let .chatId(id, peerId, _):
            return UIChatListEntryId.chatId(id, peerId, -1)
        default:
            return _stableId
        }
    }
    
    private var _stableId: UIChatListEntryId
    var entryId: UIChatListEntryId {
        return _stableId
    }
    var isForum: Bool {
        return self.peer?.isForum ?? false
    }
    var isTopic: Bool {
        switch self.mode {
        case .topic:
            return true
        case .chat:
            return false
        }
    }
    
    var chatLocation: ChatLocation? {
        if let index = chatListIndex {
            return ChatLocation.peer(index.messageIndex.id.peerId)
        }
        return nil
    }

    let mentionsCount: Int32?
    let reactionsCount: Int32?

    private var date:NSAttributedString?

    private var displayLayout:(TextNodeLayout, TextNode)?

    private var messageLayout:TextViewLayout?
    private var messageSelectedLayout:TextViewLayout?
    
    private(set) var topicsLayout: ChatListTopicNameAndTextLayout?
    
    private var chatNameLayout:TextViewLayout?
    private var chatNameSelectedLayout:TextViewLayout?

    private var forumTopicNameLayout:TextViewLayout?
    private var forumTopicNameSelectedLayout:TextViewLayout?

    
    private var displaySelectedLayout:(TextNodeLayout, TextNode)?
    private var dateLayout:(TextNodeLayout, TextNode)?
    private var dateSelectedLayout:(TextNodeLayout, TextNode)?

    private var displayNode:TextNode = TextNode()
    private var displaySelectedNode:TextNode = TextNode()

    
    private let titleText:NSAttributedString?
        
    private(set) var peerNotificationSettings:PeerNotificationSettings?
    private(set) var readState:EnginePeerReadCounters?
    
    
    
    private var badgeNode:BadgeNode? = nil
    private var badgeSelectedNode:BadgeNode? = nil
    
    private var additionalBadgeNode:BadgeNode? = nil
    private var additionalBadgeSelectedNode:BadgeNode? = nil


    private let _animateArchive:Atomic<Bool> = Atomic(value: false)
    
    var animateArchive:Bool {
        return _animateArchive.swap(false)
    }
    
    let filter: ChatListFilter
    
    var isCollapsed: Bool {
        if let archiveStatus = archiveStatus {
            switch archiveStatus {
            case .collapsed:
                return context.layout != .minimisize
            default:
                return false
            }
        }
        return false
    }
    
    var canDeleteTopic: Bool {
        if isTopic, let peer = peer as? TelegramChannel, peer.isAdmin {
            if peer.hasPermission(.manageTopics) {
                return true
            }
        }
        return false
    }
    
    var hasRevealState: Bool {
        return canArchive || (groupId != .root && !isCollapsed)
    }
    
    var canArchive: Bool {
        if groupId != .root {
            return false
        }
        if context.peerId == peerId {
            return false
        }
        if case .ad = pinnedType {
            return false
        }
        let supportId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
        if self.peer?.id == supportId {
            return false
        }
        
        return true
    }
    
    let associatedGroupId: EngineChatList.Group
    
    let isMuted:Bool
    
    var hasUnread: Bool {
        return ctxBadgeNode != nil
    }
    
    let isVerified: Bool
    let isPremium: Bool
    let isScam: Bool
    let isFake: Bool

    
    private(set) var photos: [TelegramPeerPhoto] = []
    private let peerPhotosDisposable = MetaDisposable()

    
    var isOutMessage:Bool {
        if let message = message {
            return !message.flags.contains(.Incoming) && message.id.peerId != context.peerId
        }
        return false
    }
    var isRead:Bool {
        switch mode {
        case let .topic(_, data):
            if let message = message {
                if data.maxOutgoingReadId >= message.id.id {
                    return true
                }
            }
        default:
            if let peer = peer as? TelegramUser {
                if let _ = peer.botInfo {
                    return !peer.flags.contains(.isSupport)
                }
                if peer.id == context.peerId {
                    return true
                }
            }
            if let peer = peer as? TelegramChannel {
                if case .broadcast = peer.info {
                    return true
                }
            }
            
            if let readState = readState {
                if let message = message {
                    return readState.isOutgoingMessageIndexRead(MessageIndex(message))
                }
            }
        }
        
        
        return false
    }
    
    
    var isUnreadMarked: Bool {
        if let readState = readState {
            return readState.markedUnread
        }
        return false
    }
    
    var isSecret:Bool {
        if let renderedPeer = renderedPeer {
            return renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat
        } else {
            return false
        }
    }
    
    var isSending:Bool {
        if let message = message {
            return message.flags.contains(.Unsent)
        }
        return false
    }
    
    var isFailed: Bool {
        return self.hasFailed
    }
    
    var isSavedMessage: Bool {
        return peer?.id == context.peerId
    }
    var isRepliesChat: Bool {
        return peer?.id == repliesPeerId
    }
    
    
    
    let hasDraft:Bool
    private let hasFailed: Bool
    let pinnedType:ChatListPinnedType
    let activities: [PeerListState.InputActivities.Activity]
    
    var toolTip: String? {
        return messageLayout?.attributedString.string
    }
    
    private(set) var isOnline: Bool?
    
    private(set) var hasActiveGroupCall: Bool = false
    
    private var presenceManager:PeerPresenceStatusManager?
    
    let archiveStatus: HiddenArchiveStatus?
    
    private var groupItems:[EngineChatList.GroupItem.Item] = []
    
    private var textLeftCutout: CGFloat = 0.0
    let contentImageSize = CGSize(width: 16, height: 16)
    let contentImageSpacing: CGFloat = 2.0
    let contentImageTrailingSpace: CGFloat = 5.0
    private(set) var contentImageSpecs: [(message: Message, media: Media, size: CGSize)] = []


    
    init(_ initialSize:NSSize, context: AccountContext, stableId: UIChatListEntryId, pinnedType: ChatListPinnedType, groupId: EngineChatList.Group, groupItems: [EngineChatList.GroupItem.Item], messages: [Message], unreadCount: Int, activities: [PeerListState.InputActivities.Activity] = [], animateGroup: Bool = false, archiveStatus: HiddenArchiveStatus = .normal, hasFailed: Bool = false, filter: ChatListFilter = .allChats) {
        self.groupId = groupId
        self.peer = nil
        self.mode = .chat
        self.messages = messages
        self.chatListIndex = nil
        self.activities = activities
        self.context = context
        self.mentionsCount = nil
        self.reactionsCount = nil
        self._stableId = stableId
        self.pinnedType = pinnedType
        self.renderedPeer = nil
        self.forumTopicData = nil
        self.forumTopicItems = []
        self.associatedGroupId = .root
        self.isMuted = false
        self.isOnline = nil
        self.archiveStatus = archiveStatus
        self.groupItems = groupItems
        self.isVerified = false
        self.isPremium = false
        self.isScam = false
        self.isFake = false
        self.filter = filter
        self.hasFailed = hasFailed
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let _ = titleText.append(string: strings().chatListArchivedChats, color: theme.chatList.textColor, font: .medium(.title))
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        
        
        self.titleText = titleText
        
        
        hasDraft = false
        
    

        
        if let message = messages.first {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor,range: range)
            self.date = date.copy() as? NSAttributedString
            
            dateLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
        }
        
        
        let mutedCount = unreadCount
        
        self.highlightText = nil
        self.draft = nil
        
        photo = .ArchivedChats
        self.titleMode = .normal
        
        super.init(initialSize)
        
        if case .hidden(true) = archiveStatus {
            hideItem(animated: false, reload: false)
        }
        
        
        _ = _animateArchive.swap(animateGroup)
        
        if mutedCount > 0  {
            badgeNode = BadgeNode(.initialize(string: "\(mutedCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), theme.chatList.badgeMutedBackgroundColor)
            badgeSelectedNode = BadgeNode(.initialize(string: "\(mutedCount)", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
        }
        
        let messageText: NSAttributedString
        if groupItems.count == 1 {
            messageText = chatListText(account: context.account, for: message, messagesCount: 1, folder: true)
        } else {
            let textString = NSMutableAttributedString(string: "")
            var isFirst = true
            for item in groupItems {
                if let chatMainPeer = item.peer.chatMainPeer?._asPeer() {
                    let peerTitle = chatMainPeer.compactDisplayTitle
                    if !peerTitle.isEmpty {
                        if isFirst {
                            isFirst = false
                        } else {
                            textString.append(.initialize(string: ", ", color: theme.chatList.textColor, font: .normal(.text)))
                        }
                        textString.append(.initialize(string: peerTitle, color: item.isUnread ? theme.chatList.textColor : theme.chatList.grayTextColor, font: .normal(.text)))
                    }
                }
            }
            messageText = textString
        }
        if let messageText = messageText.mutableCopy() as? NSMutableAttributedString, !messageText.string
            .isEmpty {
            self.messageLayout = .init(messageText, maximumNumberOfLines: 2)
            let selectedText:NSMutableAttributedString = messageText.mutableCopy() as! NSMutableAttributedString
            if let color = selectedText.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedText.range)
                self.messageSelectedLayout = .init(selectedText, maximumNumberOfLines: 2)
            }
        }

        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    private let highlightText: String?
    
    private let draft:EngineChatList.Draft?
    
    enum Mode {
        case chat
        case topic(Int64, MessageHistoryThreadData)
        
        var threadId: Int64? {
            switch self {
            case let .topic(threadId, _):
                return threadId
            default:
                return nil
            }
        }
        var threadData: MessageHistoryThreadData? {
            switch self {
            case let .topic(_, data):
                return data
            default:
                return nil
            }
        }
    }
    enum TitleMode {
        case normal
        case forumInfo
    }
    
    let mode: Mode
    let titleMode: TitleMode
    
  
    
    
    init(_ initialSize:NSSize, context: AccountContext, stableId: UIChatListEntryId, mode: Mode, messages: [Message], index: ChatListIndex? = nil, readState:EnginePeerReadCounters? = nil, draft:EngineChatList.Draft? = nil, pinnedType:ChatListPinnedType = .none, renderedPeer:EngineRenderedPeer, peerPresence: EnginePeer.Presence? = nil, forumTopicData: EngineChatList.ForumTopicData? = nil, forumTopicItems:[EngineChatList.ForumTopicData] = [], activities: [PeerListState.InputActivities.Activity] = [], highlightText: String? = nil, associatedGroupId: EngineChatList.Group = .root, isMuted:Bool = false, hasFailed: Bool = false, hasUnreadMentions: Bool = false, hasUnreadReactions: Bool = false, showBadge: Bool = true, filter: ChatListFilter = .allChats, titleMode: TitleMode = .normal) {
        
        
        var draft = draft
        
        if let peer = renderedPeer.chatMainPeer?._asPeer() as? TelegramChannel {
            if !peer.hasPermission(.sendMessages) {
                draft = nil
            }
        }
        
        if let value = draft {
            if value.text.isEmpty {
                draft = nil
            }
        }
        let supportId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))

        if let peerPresence = peerPresence?._asPresence(), context.peerId != renderedPeer.peerId, renderedPeer.peerId != supportId {
            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
            let relative = relativeUserPresenceStatus(peerPresence, timeDifference: context.timeDifference, relativeTo: Int32(timestamp))
            switch relative {
            case .online:
                self.isOnline = true
            default:
                self.isOnline = false
            }
        } else {
            self.isOnline = nil
        }
        
        if let peer = renderedPeer.chatMainPeer?._asPeer() as? TelegramChannel, peer.flags.contains(.hasActiveVoiceChat) {
            self.hasActiveGroupCall = mode.threadId == nil
        }
    
        self.mode = mode
        self.titleMode = titleMode
        self.chatListIndex = index
        self.renderedPeer = renderedPeer
        self.context = context
        self.messages = messages
        self.activities = activities
        self.pinnedType = pinnedType
        self.archiveStatus = nil
        self.forumTopicData = forumTopicData
        self.forumTopicItems = forumTopicItems
        self.hasDraft = draft != nil
        self.draft = draft
        self.peer = renderedPeer.chatMainPeer?._asPeer()
        self.groupId = .root
        self.hasFailed = hasFailed
        self.filter = filter
        self.associatedGroupId = associatedGroupId
        self.highlightText = highlightText
        self._stableId = stableId
        if let peer = peer {
            self.isVerified = peer.isVerified
            self.isPremium = peer.isPremium && peer.id != context.peerId
            self.isScam = peer.isScam
            self.isFake = peer.isFake
        } else {
            self.isVerified = false
            self.isScam = false
            self.isFake = false
            self.isPremium = false
        }
        
       
        self.isMuted = isMuted
        self.readState = readState
        
        
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        switch mode {
        case .chat:
            let _ = titleText.append(string: peer?.id == context.peerId ? strings().peerSavedMessages : peer?.displayTitle, color: renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat ? theme.chatList.secretChatTextColor : theme.chatList.textColor, font: .medium(.title))

        case let .topic(_, data):
            let _ = titleText.append(string: data.info.title, color: theme.chatList.textColor, font: .medium(.title))
        }
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        self.titleText = titleText
        
        if !forumTopicItems.isEmpty, let message = messages.first {
            self.topicsLayout = .init(context, message: message, items: forumTopicItems, draft: draft)
        }
    
        
        if case let .ad(item) = pinnedType {
            let sponsored:NSMutableAttributedString = NSMutableAttributedString()
            let range: NSRange
            switch item.promoInfo.content {
            case let .psa(type, _):
                range = sponsored.append(string: localizedPsa("psa.chatlist", type: type), color: theme.colors.grayText, font: .normal(.short))
            case .proxy:
                range = sponsored.append(string: strings().chatListSponsoredChannel, color: theme.colors.grayText, font: .normal(.short))
            }
            sponsored.setSelected(color: theme.colors.underSelectedColor, range: range)
            self.date = sponsored
            dateLayout = TextNode.layoutText(maybeNode: nil,  sponsored, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  sponsored, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
        } else if let message = messages.first, forumTopicItems.isEmpty {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor, range: range)
            self.date = date.copy() as? NSAttributedString
            
            dateLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
            dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)
            
            
            var author: Peer?
            if message.isImported, let info = message.forwardInfo {
                if let peer = info.author {
                    author = peer
                } else if let signature = info.authorSignature {
                    author = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0)), accessHash: nil, firstName: signature, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [])
                }
            } else {
                author = message.author
            }
            
            if let author = author, let peer = peer, peer as? TelegramUser == nil, !peer.isChannel, draft == nil {
                if !(message.effectiveMedia is TelegramMediaAction) {
                    var peerText: String = (author.id == context.account.peerId ? "\(strings().chatListYou)" : author.displayTitle)
                    
                    let topicNameAttributed = NSMutableAttributedString()

                    if let forumTopicData = forumTopicData, peer.isForum {
                        _ = topicNameAttributed.append(string: forumTopicData.title, color: theme.chatList.peerTextColor, font: .normal(.text))
                    } else if peer.isForum, titleMode == .forumInfo, case let .topic(_, data) = mode {
                        peerText = author.compactDisplayTitle
                        _ = topicNameAttributed.append(string: data.info.title, color: theme.chatList.peerTextColor, font: .normal(.text))
                    }

                    if !topicNameAttributed.string.isEmpty {
                        self.forumTopicNameLayout = .init(topicNameAttributed, maximumNumberOfLines: 1)
                        
                        let selectedText:NSMutableAttributedString = topicNameAttributed.mutableCopy() as! NSMutableAttributedString
                        selectedText.addAttribute(.foregroundColor, value: theme.colors.underSelectedColor, range: selectedText.range)

                        self.forumTopicNameSelectedLayout = .init(selectedText, maximumNumberOfLines: 1)
                    }
                    
                    let attr = NSMutableAttributedString()
                    _ = attr.append(string: peerText, color: theme.chatList.peerTextColor, font: .normal(.text))
                    attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                    
                    if !attr.string.isEmpty {
                        self.chatNameLayout = .init(attr, maximumNumberOfLines: 1)
                        
                        let selectedText:NSMutableAttributedString = attr.mutableCopy() as! NSMutableAttributedString
                        if let color = selectedText.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                            selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedText.range)
                        }
                        self.chatNameSelectedLayout = .init(selectedText, maximumNumberOfLines: 1)
                    }
                }
            }
            
            let contentImageFillSize = CGSize(width: 8.0, height: contentImageSize.height)
            _ = contentImageFillSize
            let isSecret: Bool
            isSecret = renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat
            
            if draft == nil, !isSecret, forumTopicItems.isEmpty {
                for message in messages {
                    inner: for media in message.media {
                        if !message.containsSecretMedia {
                            if let image = media as? TelegramMediaImage {
                                if let _ = largestImageRepresentation(image.representations) {
                                    let fitSize = contentImageSize
                                    contentImageSpecs.append((message, image, fitSize))
                                }
                                break inner
                            } else if let file = media as? TelegramMediaFile {
                                if file.isVideo, !file.isInstantVideo, let _ = file.dimensions, !file.probablySticker {
                                    let fitSize = contentImageSize
                                    contentImageSpecs.append((message, file, fitSize))
                                }
                                break inner
                            }
                        }
                    }
                }
            }
        }
        
        contentImageSpecs = Array(contentImageSpecs.prefix(3))
        
        for i in 0 ..< contentImageSpecs.count {
            if i != 0 {
                textLeftCutout += contentImageSpacing
            }
            textLeftCutout += contentImageSpecs[i].size.width
            if i == contentImageSpecs.count - 1 {
                textLeftCutout += contentImageTrailingSpace
            }
        }
        
        if hasUnreadMentions {
            self.mentionsCount = 1
        } else {
            self.mentionsCount = nil
        }
       
        if hasUnreadReactions {
            self.reactionsCount = 1
        } else {
            self.reactionsCount = nil
        }
        
        let isEmpty: Bool
        
        switch mode {
        case .topic:
            isEmpty = titleMode == .normal
        case .chat:
            isEmpty = false
        }
        if let peer = peer, peer.id != context.peerId && peer.id != repliesPeerId, !isEmpty {
            self.photo = .PeerAvatar(peer, peer.displayLetters, peer.smallProfileImage, nil, nil, peer.isForum)
        } else {
            self.photo = .Empty
        }
        
        super.init(initialSize)
        
        if showBadge {
            
            let isMuted = isMuted || (readState?.isMuted ?? false)
            
            if let unreadCount = readState?.count, unreadCount > 0, mentionsCount == nil || (unreadCount > 1 || mentionsCount! != unreadCount)  {

                badgeNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)
                badgeSelectedNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
            } else if isUnreadMarked && mentionsCount == nil {
                badgeNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)
                badgeSelectedNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
            }
        }
       
        
      
        if let _ = self.isOnline, let presence = peerPresence?._asPresence() {
            presenceManager = PeerPresenceStatusManager(update: { [weak self] in
                self?.isOnline = false
                self?.redraw(animated: true)
            })
            presenceManager?.reset(presence: presence, timeDifference: Int32(context.timeDifference))
        }
        if forumTopicItems.isEmpty {
            var messageText: NSAttributedString?
            var textCutout: TextViewCutout?
            if case let .ad(promo) = pinnedType, message == nil {
                switch promo.promoInfo.content {
                case let .psa(_, message):
                    if let message = message {
                        let attr = NSMutableAttributedString()
                        _ = attr.append(string: message, color: theme.colors.grayText, font: .normal(.text))
                        attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                        messageText = attr
                    }
                default:
                    break
                }
            } else {
                messageText = chatListText(account: context.account, for: message, messagesCount: messages.count, draft: draft, folder: false, applyUserName: false, isPremium: context.isPremium)
                if !textLeftCutout.isZero {
                    textCutout = TextViewCutout(topLeft: CGSize(width: textLeftCutout, height: 14))
                }
            }
            if let messageText = messageText, !messageText.string.isEmpty {
                self.messageLayout = .init(messageText, maximumNumberOfLines: chatNameLayout != nil ? 1 : 2, cutout: textCutout)
                
                let selectedText:NSMutableAttributedString = messageText.mutableCopy() as! NSMutableAttributedString
                if let color = selectedText.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                    selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedText.range)
                }
                self.messageSelectedLayout = .init(selectedText, maximumNumberOfLines: chatNameLayout != nil ? 1 : 2, cutout: textCutout)
            }
        }
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
        
        if let peer = peer, peer.isPremium, peer.id != context.peerId, peer.hasVideo {
            self.photos = syncPeerPhotos(peerId: peer.id)
            let signal = peerPhotos(context: context, peerId: peer.id, force: false) |> deliverOnMainQueue
            peerPhotosDisposable.set(signal.start(next: { [weak self] photos in
                if self?.photos != photos {
                    self?.photos = photos
                    self?.redraw(animated: true, options: .effectFade)
                }
            }))
        }
    }
    
    let margin:CGFloat = 9
    
    
    var isPinned: Bool {
        switch pinnedType {
        case .some:
            return true
        case .last:
            return true
        default:
            return false
        }
    }
    var isClosedTopic: Bool {
        switch self.mode {
        case let .topic(_, threadData):
            return threadData.isClosed
        case .chat:
            return false
        }
    }
    
    var badgeMuted: Bool {
        let isMuted = isMuted || (readState?.isMuted ?? false)

        return isMuted
    }
    
    var isLastPinned: Bool {
        switch pinnedType {
        case .last:
            return true
        default:
            return false
        }
    }
    
    
    var isFixedItem: Bool {
        switch pinnedType {
        case .some, .ad, .last:
            return true
        default:
            return false
        }
    }
    var canResortPinned: Bool {
        switch mode {
        case .topic:
            if let peer = self.peer as? TelegramChannel {
                return peer.hasPermission(.pinMessages)
            } else {
                return false
            }
        default:
            return true
        }
    }

    var isAd: Bool {
        switch pinnedType {
        case .ad:
            return true
        default:
            return false
        }
    }
    
    var badIcon: CGImage {
        return isScam ? theme.icons.scam : theme.icons.fake
    }
    var badHighlightIcon: CGImage {
        return isScam ? theme.icons.scamActive : theme.icons.fakeActive
    }
    var titleWidth:CGFloat {
        var dateSize:CGFloat = 0
        if let dateLayout = dateLayout {
            dateSize = dateLayout.0.size.width
        }
        var offset: CGFloat = 0
        if let peer = peer, peer.id != context.peerId, let controlSize = PremiumStatusControl.controlSize(peer, false) {
            offset += controlSize.width + 4
        }
        if isMuted {
            offset += theme.icons.dialogMuteImage.backingSize.width + 4
        }
        if isSecret {
            offset += 10
        }
        if isTopic && titleMode == .normal {
            offset += 30
        } else {
            offset += 50
        }
        if isClosedTopic {
            offset += 10
        }
        return max(300, size.width) - margin * 4 - dateSize - (isOutMessage ? isRead ? 14 : 8 : 0) - offset
    }
    
    var chatNameWidth:CGFloat {
        var w:CGFloat = 0
        if let badgeNode = badgeNode {
            w += badgeNode.size.width + 5
        }
        if let _ = mentionsCount {
            w += 30
        }
        if let _ = reactionsCount {
            w += 30
        }
        if let additionalBadgeNode = additionalBadgeNode {
            w += additionalBadgeNode.size.width + 15
        }
        if isTopic && titleMode == .normal {
            w += 30
        } else {
            w += 50
        }
        return max(300, size.width) - margin * 4 - w - (isOutMessage ? isRead ? 14 : 8 : 0)
    }
    
    var messageWidth:CGFloat {
        var w: CGFloat = 0
        if let badgeNode = badgeNode {
            w += badgeNode.size.width + 5
        }
        if let _ = mentionsCount {
            w += 30
        }
        if let _ = reactionsCount {
            w += 30
        }
        if let additionalBadgeNode = additionalBadgeNode {
            w += additionalBadgeNode.size.width + 15
        }
        if isPinned && badgeNode == nil {
            w += 15
        }
        if isTopic && titleMode == .normal {
            w += 30
        } else {
            w += 50
        }
        
        return (max(300, size.width) - margin * 4) - w - (chatNameLayout != nil ? textLeftCutout : 0)
    }
    
    var leftInset:CGFloat {
        switch mode {
        case .chat:
            return 50 + (10 * 2.0);
        case .topic:
            if titleMode == .forumInfo {
                return 50 + (10 * 2.0);
            } else {
                return 30 + (10 * 2.0);
            }
        }
    }
    
    override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        
        
        
        if displayLayout == nil || !displayLayout!.0.isPerfectSized || self.oldWidth > width {
            displayLayout = TextNode.layoutText(maybeNode: displayNode,  titleText, nil, isTopic ? 2 : 1, .end, NSMakeSize(titleWidth, size.height), nil, false, .left)
        }
        
        if displaySelectedLayout == nil || !displaySelectedLayout!.0.isPerfectSized || self.oldWidth > width {
            displaySelectedLayout = TextNode.layoutText(maybeNode: displaySelectedNode,  titleText, nil, isTopic ? 2 : 1, .end, NSMakeSize(titleWidth, size.height), nil, true, .left)
        }
        
        if let forumTopicNameLayout = forumTopicNameLayout, let chatNameLayout = self.chatNameLayout {
            var width = chatNameWidth / 2 - 20
            chatNameLayout.measure(width: width)
            chatNameSelectedLayout?.measure(width: width)
            
            width = chatNameWidth - chatNameLayout.layoutSize.width - 20
            forumTopicNameLayout.measure(width: width)
            forumTopicNameSelectedLayout?.measure(width: width)
        } else {
            chatNameLayout?.measure(width: chatNameWidth)
            chatNameSelectedLayout?.measure(width: chatNameWidth)
        }
        

        messageLayout?.measure(width: messageWidth)
        messageSelectedLayout?.measure(width: messageWidth)

        self.topicsLayout?.measure(messageWidth)
   
        return result
    }
    
    
    var markAsUnread: Bool {
        return !isSecret && !isUnreadMarked && badgeNode == nil && mentionsCount == nil
    }
    
    func collapseOrExpandArchive() {
        ChatListRowItem.collapseOrExpandArchive(context: context)
    }
    
    static func collapseOrExpandArchive(context: AccountContext) {
        context.bindings.mainController().chatList.collapseOrExpandArchive()
    }
    
    static func toggleHideArchive(context: AccountContext) {
        context.bindings.mainController().chatList.toggleHideArchive()
    }
    
    func toggleHideArchive() {
        ChatListRowItem.toggleHideArchive(context: context)
    }

    func toggleUnread() {
        if let peerId = peerId {
            switch mode {
            case .chat:
                _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: nil).start()
            case .topic:
                break
            }
        }
    }
    
    func toggleMuted() {
        if let peerId = peerId {
            ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted, threadId: self.mode.threadId)
        }
    }
    func delete() {
        if let peerId = peerId {
            let signal = removeChatInteractively(context: context, peerId: peerId, threadId: self.mode.threadId, userId: peer?.id)
            _ = signal.start()
        }
    }
    
    static func toggleMuted(context: AccountContext, peerId: PeerId, isMuted: Bool, threadId: Int64?) {
        if isMuted {
            _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: threadId).start()
        } else {
            var options:[ModalOptionSet] = []
            
            options.append(ModalOptionSet(title: strings().chatListMute1Hour, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute4Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute8Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute1Day, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute3Days, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMuteForever, selected: true, editable: true))
            
            let intervals:[Int32] = [60 * 60, 60 * 60 * 4, 60 * 60 * 8, 60 * 60 * 24, 60 * 60 * 24 * 3, Int32.max]
            
            showModal(with: ModalOptionSetController(context: context, options: options, selectOne: true, actionText: (strings().chatInputMute, theme.colors.accent), title: strings().peerInfoNotifications, result: { result in
                
                for (i, option) in result.enumerated() {
                    inner: switch option {
                    case .selected:
                        _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: intervals[i]).start()
                        break
                    default:
                        break inner
                    }
                }
                
            }), for: context.window)
        }
    }
    
    func togglePinned() {
        if let peerId = peerId {
            ChatListRowItem.togglePinned(context: context, peerId: peerId, isPinned: self.isPinned, mode: self.mode, filter: filter, associatedGroupId: associatedGroupId)
        }
    }
    
    static func togglePinned(context: AccountContext, peerId: PeerId, isPinned: Bool, mode: ChatListRowItem.Mode, filter: ChatListFilter, associatedGroupId: EngineChatList.Group) {
        
        
        switch mode {
        case let .topic(threadId, _):
            let signal = context.engine.peers.toggleForumChannelTopicPinned(id: peerId, threadId: threadId) |> deliverOnMainQueue
            _ = signal.start(error: { error in
                switch error {
                case let .limitReached(count):
                    if context.isPremium {
                        alert(for: context.window, info: strings().chatListContextPinErrorNew2)
                    } else {
                        showPremiumLimit(context: context, type: .pin)
                    }
                default:
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        case .chat:
            let location: TogglePeerChatPinnedLocation
            let itemId: PinnedItemId = .peer(peerId)
            if case .filter = filter {
                location = .filter(filter.id)
            } else {
                location = .group(associatedGroupId._asGroup())
            }
            let context = context
            
            _ = (context.engine.peers.toggleItemPinned(location: location, itemId: itemId) |> deliverOnMainQueue).start(next: { result in
                switch result {
                case .limitExceeded:
                    if context.isPremium {
                        confirm(for: context.window, information: strings().chatListContextPinErrorNew2, okTitle: strings().alertOK, cancelTitle: "", thridTitle: strings().chatListContextPinErrorNewSetupFolders, successHandler: { result in
                            switch result {
                            case .thrid:
                                context.bindings.rootNavigation().push(ChatListFiltersListController(context: context))
                            default:
                                break
                            }
                        })

                    } else {
                        if case .filter = filter {
                            showPremiumLimit(context: context, type: .pinInFolders(.group(filter.id)))
                        } else {
                            if case .archive = associatedGroupId {
                                showPremiumLimit(context: context, type: .pinInArchive)
                            } else {
                                showPremiumLimit(context: context, type: .pin)
                            }
                        }
                    }
                default:
                    break
                }
            })
        }
    }
    
    func toggleArchive() {
        ChatListRowItem.toggleArchive(context: context, associatedGroupId: associatedGroupId, peerId: peerId)
    }
    
    static func toggleArchive(context: AccountContext, associatedGroupId: EngineChatList.Group?, peerId: PeerId?) {
        if let peerId = peerId {
            switch associatedGroupId {
            case .root:
                context.bindings.mainController().chatList.setAnimateGroupNextTransition(EngineChatList.Group.archive)
                _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .archive).start()
            default:
                _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .root).start()
            }
        }
    }
    
    static func toggleTopic(context: AccountContext, peerId: PeerId, threadId: Int64, isClosed: Bool) {
        _ = context.engine.peers.setForumChannelTopicClosed(id: peerId, threadId: threadId, isClosed: !isClosed).start()
    }
    
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {

        let context = self.context
        let peerId = self.peerId
        let peer = self.peer
        let filter = self.filter
        let isMuted = self.isMuted
        let associatedGroupId = self.associatedGroupId
        let isAd = self.isAd
        let renderedPeer = self.renderedPeer
        let canArchive = self.canArchive
        let groupId = self.groupId
        let markAsUnread = self.markAsUnread
        let isPinned = self.isPinned
        let archiveStatus = archiveStatus
        let isSecret = self.isSecret
        let isUnread = badgeNode != nil || mentionsCount != nil || isUnreadMarked
        let threadId = self.mode.threadId
        let mode = self.mode
        let isClosedTopic = self.isClosedTopic
        let isForum = self.isForum
        
       
        let deleteChat:()->Void = {
            if let peerId = peerId {
                let signal = removeChatInteractively(context: context, peerId: peerId, threadId: threadId, userId: peer?.id)
                _ = signal.start()
            }
        }
        
        let togglePin:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.togglePinned(context: context, peerId: peerId, isPinned: isPinned, mode: mode, filter: filter, associatedGroupId: associatedGroupId)
            }
        }
        
        let toggleArchive:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.toggleArchive(context: context, associatedGroupId: associatedGroupId, peerId: peerId)
            }
        }
        
        let toggleMute:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted, threadId: threadId)
            }
        }
        let toggleTopic:()->Void = {
            if let peerId = peerId, let threadId = threadId {
                ChatListRowItem.toggleTopic(context: context, peerId: peerId, threadId: threadId, isClosed: isClosedTopic)
            }
        }
        
        if case let .topic(_, data) = self.mode, let peer = peer as? TelegramChannel {
            
            var items:[ContextMenuItem] = []
            
            if peer.hasPermission(.pinMessages) {
                items.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
            }

            
            items.append(ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: toggleMute, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
            
            if data.isOwnedByMe || peer.isAdmin {
                items.append(ContextMenuItem(!isClosedTopic ? strings().chatListContextPause : strings().chatListContextStart, handler: toggleTopic, itemImage: !isClosedTopic ? MenuAnimation.menu_pause.value : MenuAnimation.menu_play.value))
                
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().chatListContextDelete, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            
            
            return .single(items)
        }
        
        let cachedData:Signal<CachedPeerData?, NoError>
        if let peerId = peerId {
            cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
        } else {
            cachedData = .single(nil)
        }
        
        let soundsDataSignal = combineLatest(queue: .mainQueue(), appNotificationSettings(accountManager: context.sharedContext.accountManager), context.engine.peers.notificationSoundList(), context.account.postbox.transaction { transaction -> TelegramPeerNotificationSettings? in
            if let peerId = peerId {
                return transaction.getPeerNotificationSettings(id: peerId) as? TelegramPeerNotificationSettings
            } else {
                return nil
            }
        })

        return combineLatest(queue: .mainQueue(), chatListFilterPreferences(engine: context.engine), cachedData, soundsDataSignal) |> take(1) |> map { filters, cachedData, soundsData -> [ContextMenuItem] in
            
            var items:[ContextMenuItem] = []
            
            let canDeleteForAll: Bool?
            if let cachedData = cachedData as? CachedChannelData {
                canDeleteForAll = cachedData.flags.contains(.canDeleteHistory)
            } else {
                canDeleteForAll = nil
            }
            
            var firstGroup:[ContextMenuItem] = []
            var secondGroup:[ContextMenuItem] = []
            var thirdGroup:[ContextMenuItem] = []

            if let mainPeer = peer, let peerId = peerId, let peer = renderedPeer?.peers[peerId] {
                                    
                if !isAd && groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
                }
                
                if groupId == .root, (canArchive || associatedGroupId != .root), filter == .allChats {
                    secondGroup.append(ContextMenuItem(associatedGroupId == .root ? strings().chatListSwipingArchive : strings().chatListSwipingUnarchive, handler: toggleArchive, itemImage: associatedGroupId == .root ? MenuAnimation.menu_archive.value : MenuAnimation.menu_unarchive.value))
                }
                
                if context.peerId != peer.id, !isAd {
                    let muteItem = ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: toggleMute, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value)
                    
                    let sound: ContextMenuItem = ContextMenuItem(strings().chatListContextSound, handler: {
                        
                    }, itemImage: MenuAnimation.menu_music.value)
                    
                    let soundList = ContextMenu()
                    
                    
                    let selectedSound: PeerMessageSound
                    if let peerNotificationSettings = soundsData.2 {
                        selectedSound = peerNotificationSettings.messageSound
                    } else {
                        selectedSound = .default
                    }
                    
                    let playSound:(PeerMessageSound) -> Void = { tone in
                        let effectiveTone: PeerMessageSound
                        if tone == .default {
                            effectiveTone = soundsData.0.tone
                        } else {
                            effectiveTone = tone
                        }
                        
                        if effectiveTone != .default && effectiveTone != .none {
                            let path = fileNameForNotificationSound(postbox: context.account.postbox, sound: effectiveTone, defaultSound: nil, list: soundsData.1)
                            
                            _ = path.start(next: { resource in
                                if let resource = resource {
                                    let path = resourcePath(context.account.postbox, resource)
                                    SoundEffectPlay.play(postbox: context.account.postbox, path: path)
                                }
                            })
                        }
                    }
                    
                    let updateSound:(PeerMessageSound)->Void = { tone in
                        playSound(tone)
                        _ = context.engine.peers.updatePeerNotificationSoundInteractive(peerId: peerId, threadId: threadId, sound: tone).start()

                    }
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .default, default: nil, list: nil), handler: {
                        updateSound(.default)
                    }, hover: {
                        playSound(.default)
                    }, state: selectedSound == .default ? .on : nil))
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .none, default: nil, list: nil), handler: {
                        updateSound(.none)
                    }, hover: {
                        playSound(.none)
                    }, state: selectedSound == .none ? .on : nil))
                    soundList.addItem(ContextSeparatorItem())
                    
                    
                    
                    if let sounds = soundsData.1 {
                        for sound in sounds.sounds {
                            let tone: PeerMessageSound = .cloud(fileId: sound.file.fileId.id)
                            soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .cloud(fileId: sound.file.fileId.id), default: nil, list: sounds), handler: {
                                updateSound(tone)
                            }, hover: {
                                playSound(tone)
                            }, state: selectedSound == .cloud(fileId: sound.file.fileId.id) ? .on : nil))
                        }
                        if !sounds.sounds.isEmpty {
                            soundList.addItem(ContextSeparatorItem())
                        }
                    }
                    
                 
                    for i in 0 ..< 12 {
                        let sound: PeerMessageSound = .bundledModern(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    soundList.addItem(ContextSeparatorItem())
                    for i in 0 ..< 8 {
                        let sound: PeerMessageSound = .bundledClassic(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    
                    
                    sound.submenu = soundList
                    
                    
                    if !isMuted {
                        let submenu = ContextMenu()
                        submenu.addItem(ContextMenuItem(strings().chatListMute1Hour, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: 60 * 60 * 1).start()
                        }, itemImage: MenuAnimation.menu_mute_for_1_hour.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMute3Days, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: 60 * 60 * 24 * 3).start()
                        }, itemImage: MenuAnimation.menu_mute_for_2_days.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMuteForever, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: Int32.max).start()
                        }, itemImage: MenuAnimation.menu_mute.value))
                        
                        submenu.addItem(ContextSeparatorItem())
                        submenu.addItem(sound)
                        
                        muteItem.submenu = submenu
                    }
                    /*
                     else {
                         let submenu = ContextMenu()
                         submenu.addItem(sound)
                         muteItem.submenu = submenu
                     }
                     
                     */
                    
                    firstGroup.append(muteItem)
                }
                
                if mainPeer is TelegramUser {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer._asPeer(), mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_clear_history.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteChat, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                
                if !isSecret {
                    if markAsUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsUnread, handler: {
                            _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: true).start()
                        }, itemImage: MenuAnimation.menu_unread.value))
                        
                    } else if isUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                            _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: false).start()
                        }, itemImage: MenuAnimation.menu_read.value))
                    }
                }
                
                if isAd {
                    firstGroup.append(ContextMenuItem(strings().chatListContextHidePromo, handler: {
                        context.bindings.mainController().chatList.hidePromoItem(peerId)
                    }, itemImage: MenuAnimation.menu_archive.value))
                }
                if let peer = peer._asPeer() as? TelegramGroup, !isAd {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_delete.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteAndExit, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                } else if let peer = peer._asPeer() as? TelegramChannel, !isAd, !peer.flags.contains(.hasGeo) {
                    
                    if case .broadcast = peer.info {
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveChannel, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_leave.value))
                    } else if !isAd {
                        if peer.addressName == nil {
                            thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                                clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                            }, itemImage: MenuAnimation.menu_clear_history.value))
                        } 
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveGroup, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    }
                }
                
            } else {
                if !isAd, groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: isPinned ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
                }
            }
            
            if groupId != .root, context.layout != .minimisize, let archiveStatus = archiveStatus {
                switch archiveStatus {
                case .collapsed:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionExpand , handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_expand.value))
                default:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionCollapse, handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_collapse.value))
                }
            }
            
            var submenu: [ContextMenuItem] = []
            if let peerId = peerId, peerId.namespace != Namespaces.Peer.SecretChat {
                for item in filters.list {
                    inner: switch item {
                    case .allChats:
                        break inner;
                    case let .filter(_, _, _, data):
                        let menuItem = ContextMenuItem(item.title, handler: {
                            
                            let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
                            
                            let isEnabled = data.includePeers.peers.contains(peerId) || data.includePeers.peers.count < limit
                            if isEnabled {
                                _ = context.engine.peers.updateChatListFiltersInteractively({ list in
                                    var list = list
                                    for (i, folder) in list.enumerated() {
                                        if folder.id == item.id, var folderData = folder.data {
                                            if data.includePeers.peers.contains(peerId) {
                                                var peers = folderData.includePeers.peers
                                                peers.removeAll(where: { $0 == peerId })
                                                folderData.includePeers.setPeers(peers)
                                            } else {
                                                folderData.includePeers.setPeers(folderData.includePeers.peers + [peerId])
                                            }
                                            list[i] = list[i].withUpdatedData(folderData)
                                        }
                                    }
                                    return list
                                }).start()
                            } else {
                                if context.isPremium {
                                    alert(for: context.window, info: strings().chatListFilterIncludeLimitReached)
                                } else {
                                    showPremiumLimit(context: context, type: .chatInFolders)
                                }
                            }
                           
                        }, state: data.includePeers.peers.contains(peerId) ? .on : nil, itemImage: FolderIcon(item).emoticon.drawable.value)
                        submenu.append(menuItem)
                    }
                }
            }
            
            if !submenu.isEmpty {
                let item = ContextMenuItem(strings().chatListFilterAddToFolder, itemImage: MenuAnimation.menu_add_to_folder.value)
                let menu = ContextMenu()
                for item in submenu {
                    menu.addItem(item)
                }
                item.submenu = menu
                secondGroup.append(item)
            }
            
            if !firstGroup.isEmpty {
                items.append(contentsOf: firstGroup)
            }
            if !secondGroup.isEmpty {
                if !firstGroup.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(contentsOf: secondGroup)
            }
            if !thirdGroup.isEmpty {
                if !firstGroup.isEmpty || !secondGroup.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(contentsOf: thirdGroup)
            }
            
            return items
        }
    }
    
    var ctxDisplayLayout:(TextNodeLayout, TextNode)? {
        if isActiveSelected {
            return displaySelectedLayout
        }
        return displayLayout
    }
    
    var isActiveSelected: Bool {
        return isSelected && context.layout != .single && !(isForum && !isTopic)
    }
    
    var ctxChatNameLayout:TextViewLayout? {
        if isActiveSelected {
            return chatNameSelectedLayout
        }
        return chatNameLayout
    }
    
    var ctxForumTopicNameLayout:TextViewLayout? {
        if isActiveSelected {
            return forumTopicNameSelectedLayout
        }
        return forumTopicNameLayout
    }
    
    
    var ctxMessageText:TextViewLayout? {
        if self.activities.isEmpty {
            if isActiveSelected {
                return messageSelectedLayout
            }
            return messageLayout
        }
        return nil
    }
    
    var ctxDateLayout:(TextNodeLayout, TextNode)? {
        if isActiveSelected {
            return dateSelectedLayout
        }
        return dateLayout
    }
    
    var ctxBadgeNode:BadgeNode? {
        if isActiveSelected {
            return badgeSelectedNode
        }
        return badgeNode
    }
    
//    var ctxBadge: Badge? {
//        if isSelected && context.layout != .single {
//            return badgeSelected
//        }
//        return badge
//    }
    
    var ctxAdditionalBadgeNode:BadgeNode? {
        if isActiveSelected {
            return additionalBadgeSelectedNode
        }
        return additionalBadgeNode
    }
    
    
    override var instantlyResize: Bool {
        return true
    }

    deinit {
    }
    
    override func viewClass() -> AnyClass {
        return ChatListRowView.self
    }
  
    override var height: CGFloat {
        if let archiveStatus = archiveStatus, context.layout != .minimisize {
            switch archiveStatus {
            case .collapsed:
                return 30
            default:
                return 70
            }
        }
        if context.layout == .minimisize {
            return 70
        }
        
        switch mode {
        case .chat:
            return 70
        case .topic:
            return 53 + (displayLayout?.0.size.height ?? 17)
        }
    }
    
}
