import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter_sms/flutter_sms.dart';
// import 'package:telephony/telephony.dart'; // Discontinued package
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_mailer/flutter_mailer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import '../utils/logger.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/message_template.dart';
import '../models/contact_info.dart';
import '../models/contact_group.dart';
import '../models/recipient_info.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';
import '../utils/helpers.dart';
import '../widgets/expandable_contact_tile.dart';
import '../widgets/recipients_screen.dart';
import 'create_template_screen.dart';
import 'edit_group_members_screen.dart';

class ConversationScreen extends StatefulWidget {
  final Conversation conversation;
  final List<MessageTemplate> templates;
  final Function(Message) onMessageSent;

  const ConversationScreen({
    super.key,
    required this.conversation,
    required this.templates,
    required this.onMessageSent,
  });

  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _currentDraft;
  String? _savedDraftDuringEdit;
  // FOR RELEASE: Always send individually (no toggle)
  final bool _sendAsIndividual = true; // Always individual for release
  String _searchQuery = '';
  bool _showSearchBar = false;
  final TextEditingController _searchTextController = TextEditingController();
  String? _editingMessageId;
  double _editingBubbleYPosition =
      0.3; // Store the Y position of editing bubble
  final Map<String, GlobalKey> _messageKeys = {}; // Track message widget keys

  // Track per-recipient status: messageId -> recipientKey -> status
  // NOTE: This is now deprecated in favor of message.recipientHistory
  static final Map<String, Map<String, String>> _recipientStatuses = {};

  // Track original recipients for each message: messageId -> Set of contactInfo keys
  // NOTE: This is now deprecated in favor of message.recipientHistory
  static final Map<String, Set<String>> _messageOriginalRecipients = {};

  List<Message> get _filteredMessages {
    if (_searchQuery.isEmpty) {
      return widget.conversation.messages;
    }
    return widget.conversation.messages.where((message) {
      return message.content.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDraft();
    // COMMENTED OUT FOR RELEASE - NO TOGGLE NEEDED
    // _loadSendTypePreference();
    _messageController.addListener(_saveDraft);
    _refreshMessageStatuses();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh data when app becomes active again
    if (state == AppLifecycleState.resumed) {
      _refreshMessageStatuses();
      _refreshConversationContacts();
    }
  }

  Future<void> _refreshConversationContacts() async {
    try {
      // Load groups and validate to get updated contact names
      final groups = await StorageService.loadGroups();
      final validatedGroups =
          await StorageService.validateAndCleanGroups(groups);

      // Find this conversation's group
      final matchingGroup = validatedGroups.firstWhere(
        (g) => g.id == widget.conversation.id,
        orElse: () => ContactGroup(
          id: widget.conversation.id,
          name: '',
          contacts: widget.conversation.contacts,
        ),
      );

      // Update conversation contacts with fresh data
      if (mounted) {
        setState(() {
          widget.conversation.contacts = matchingGroup.contacts;
        });
        Logger.info('Conversation contacts updated with fresh device data');
      }
    } catch (e) {
      Logger.error('Error refreshing conversation contacts', e);
    }
  }

  // COMMENTED OUT FOR RELEASE - NO TOGGLE NEEDED
  // Future<void> _loadSendTypePreference() async {
  //   final sendAsIndividual = await StorageService.loadSendAsIndividual();
  //   setState(() {
  //     _sendAsIndividual = sendAsIndividual;
  //   });
  // }

  // COMMENTED OUT FOR RELEASE - NO TOGGLE NEEDED
  // Future<void> _toggleSendType() async {
  //   final newValue = !_sendAsIndividual;
  //   setState(() {
  //     _sendAsIndividual = newValue;
  //   });
  //   await StorageService.saveSendAsIndividual(newValue);
  // }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.removeListener(_saveDraft);
    _messageController.dispose();
    _editController.dispose();
    _scrollController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  void _loadDraft() {
    // Load draft for this conversation
    final draft = _getDraftForConversation(widget.conversation.id);
    if (draft != null && draft.isNotEmpty) {
      _messageController.text = draft;
      _currentDraft = draft;
    }
  }

  Future<void> _refreshMessageStatuses() async {
    try {
      // Load the latest messages from storage to get updated statuses
      final messages = await StorageService.loadMessages();
      final conversationMessages = messages
          .where((message) => message.groupId == widget.conversation.id)
          .toList();

      // Update message statuses based on recipient statuses
      for (var message in conversationMessages) {
        message.status = _calculateMessageStatusFromRecipients(message);
      }

      // Update the conversation messages with the latest statuses
      setState(() {
        widget.conversation.messages = conversationMessages;
        // Sort messages by timestamp - oldest first (normal messaging behavior)
        widget.conversation.messages.sort((a, b) => a.timestamp
            .compareTo(b.timestamp)); // Oldest first, newest at bottom
      });

      // Auto-scroll to bottom after loading messages
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      Logger.error('Error refreshing message statuses', e);
    }
  }

  MessageStatus _calculateMessageStatusFromRecipients(Message message) {
    // Check ALL recipient statuses from message history (including removed contacts)
    final allRecipientStatuses = message.recipientHistory.values.toList();

    // If no recipient statuses found, return the stored status
    if (allRecipientStatuses.isEmpty) {
      return message.status;
    }

    // Determine overall status based on ALL recipient statuses
    if (allRecipientStatuses.any((status) => status == 'Sending')) {
      return MessageStatus.sending;
    } else if (allRecipientStatuses
        .any((status) => status == 'Failed' || status == 'Cancelled')) {
      return MessageStatus.failed;
    } else if (allRecipientStatuses.every((status) =>
        status == 'SMS' || status == 'Sent' || status == 'Received')) {
      return MessageStatus.sent;
    } else {
      return MessageStatus.sent; // Default to sent if all other checks pass
    }
  }

  void _saveDraft() {
    final text = _messageController.text;
    if (text != _currentDraft) {
      _currentDraft = text;
      _saveDraftForConversation(widget.conversation.id, text);
    }
  }

  String? _getDraftForConversation(String conversationId) {
    // In a real app, you'd use SharedPreferences or a database
    // For now, we'll use a simple in-memory storage
    return _draftStorage[conversationId];
  }

  void _saveDraftForConversation(String conversationId, String draft) {
    if (draft.isEmpty) {
      _draftStorage.remove(conversationId);
    } else {
      _draftStorage[conversationId] = draft;
    }
  }

  // Static storage for drafts (in a real app, use SharedPreferences)
  static final Map<String, String> _draftStorage = {};

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Dismiss keyboard when tapping outside
        FocusScope.of(context).unfocus();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: (widget.conversation.name != null &&
                      widget.conversation.name!.isNotEmpty)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.conversation.name!,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (widget.conversation.contacts.length > 1)
                          Text(
                            '${widget.conversation.contacts.length} recipients',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF8E8E93)),
                          ),
                      ],
                    )
                  : _buildConversationAvatar(),
              backgroundColor: const Color(0xFFF9F9F9),
              elevation: 0,
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(CupertinoIcons.info),
                  onPressed: _showConversationInfo,
                ),
              ],
            ),
            body: Column(
              children: [
                // Search bar that shows/hides
                if (_showSearchBar)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFFF9F9F9),
                    child: CupertinoSearchTextField(
                      controller: _searchTextController,
                      placeholder: 'Search in conversation',
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      onSuffixTap: () {
                        setState(() {
                          _searchTextController.clear();
                          _searchQuery = '';
                          _showSearchBar = false;
                        });
                      },
                    ),
                  ),
                Expanded(
                  child: widget.conversation.messages.isEmpty
                      ? _buildEmptyMessages()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: _filteredMessages.length,
                          itemBuilder: (context, index) {
                            final message = _filteredMessages[index];
                            // Create a key for each message if it doesn't exist
                            if (!_messageKeys.containsKey(message.id)) {
                              _messageKeys[message.id] = GlobalKey();
                            }
                            // Hide the message being edited (it's shown in the overlay)
                            if (_editingMessageId == message.id) {
                              return SizedBox(
                                key: _messageKeys[message.id],
                                height:
                                    44, // Maintain space so position calculations work
                              );
                            }
                            return Container(
                              key: _messageKeys[message.id],
                              child: _buildMessageBubble(message),
                            );
                          },
                        ),
                ),
                _buildMessageInput(),
              ],
            ),
          ),
          // Blur overlay when editing - covers entire screen including header
          if (_editingMessageId != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: _cancelEditing,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: Container(
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                ),
              ),
            ),
          // Editing bubble on top of blur
          if (_editingMessageId != null)
            Positioned(
              left: 0,
              right: 0,
              top: MediaQuery.of(context).size.height * _editingBubbleYPosition,
              child: IgnorePointer(
                ignoring: false,
                child: _buildEditingBubble(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyMessages() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.chat_bubble_2,
              size: 64, color: Color(0xFF8E8E93)),
          SizedBox(height: 16),
          Text('No Messages Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8E8E93),
              )),
          SizedBox(height: 8),
          Text('Send a message to start the conversation',
              style: TextStyle(color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }

  Widget _buildEditingBubble() {
    final message = widget.conversation.messages
        .firstWhere((m) => m.id == _editingMessageId);

    return Container(
      margin: const EdgeInsets.only(
        left: 60,
        right: 4,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cancel button (X) - to the left
          GestureDetector(
            onTap: _cancelEditing,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFF8E8E93),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.xmark,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Message bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF34C759), width: 2),
              ),
              child: CupertinoTextField(
                controller: _editController,
                maxLines: null,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                ),
                padding: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: Colors.transparent),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Save button (send arrow)
          GestureDetector(
            onTap: () => _saveEditedMessage(message),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _sendAsIndividual
                    ? const Color(0xFF5856D6) // Purple for individual
                    : const Color(0xFF007AFF), // Blue for group
                shape: BoxShape.circle,
              ),
              child: Icon(
                _sendAsIndividual
                    ? CupertinoIcons.arrow_branch // Forked arrow for individual
                    : CupertinoIcons.arrow_up, // Single arrow for group
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message) {
    return GestureDetector(
      onLongPress: message.isFromMe ? () => _showMessageOptions(message) : null,
      child: Container(
        margin: EdgeInsets.only(
          left: message.isFromMe ? 60 : 16,
          right: message.isFromMe ? 4 : 60,
          top: 2,
          bottom: 2,
        ),
        child: Row(
          mainAxisAlignment: message.isFromMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Message bubble
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: message.isFromMe
                      ? (message.type == MessageType.individual
                          ? const Color(0xFF5856D6) // Purple for individual
                          : const Color(0xFF007AFF)) // Blue for group
                      : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: message.isFromMe &&
                          message.status == MessageStatus.sending
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFFCC00).withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: message.isFromMe ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ),
            // Status icon
            if (message.isFromMe) ...[
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _buildMessageStatusIcon(message.status),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /* Widget _buildEditOverlay() {
    final message = widget.conversation.messages
        .firstWhere((m) => m.id == _editingMessageId);

    return GestureDetector(
      onTap: _cancelEditing,
      child: Container(
        color: Colors.transparent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: GestureDetector(
                onTap:
                    () {}, // Prevent dismissing when tapping on the edit bubble
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Edit field
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: message.type == MessageType.individual
                              ? const Color(0xFF5856D6)
                              : const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF34C759), width: 2),
                        ),
                        child: CupertinoTextField(
                          controller: _editController,
                          maxLines: null,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          padding: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(color: Colors.transparent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            color: const Color(0xFF8E8E93),
                            borderRadius: BorderRadius.circular(12),
                            onPressed: _cancelEditing,
                            child: const Text('Cancel',
                                style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 12),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            color: const Color(0xFF34C759),
                            borderRadius: BorderRadius.circular(12),
                            child: const Text('Save',
                                style: TextStyle(fontSize: 16)),
                            onPressed: () => _saveEditedMessage(message),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  } */

  Widget _buildMessageStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor:
                AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.7)),
          ),
        );
      case MessageStatus.sent:
        return Icon(
          CupertinoIcons.checkmark,
          size: 12,
          color: Colors.white.withOpacity(0.7),
        );
      case MessageStatus.failed:
        return const Icon(
          CupertinoIcons.exclamationmark_circle_fill,
          size: 12,
          color: Color(0xFFFF3B30),
        );
      case MessageStatus.cancelled:
        return const Icon(
          CupertinoIcons.xmark_circle_fill,
          size: 12,
          color: Color(0xFFFF9500),
        );
    }
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFD1D1D6), width: 0.5)),
      ),
      child: Column(
        children: [
          // Removed: Warning banner no longer needed since contacts are properly identified
          // Message input row
          Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.plus_circle,
                    color: Color(0xFF007AFF)),
                onPressed: _showTemplateOptions,
              ),
              Expanded(
                child: CupertinoTextField(
                  controller: _messageController,
                  placeholder: 'Message',
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _sendMessage,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF5856D6), // Purple for individual (always)
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons
                        .arrow_branch, // Forked arrow for individual (always)
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTemplateOptions() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => CupertinoActionSheet(
          actions: [
            // 1. Send Individually toggle (only show for groups)
            if (widget.conversation.contacts.length > 1)
              // COMMENTED OUT FOR RELEASE - NO TOGGLE NEEDED
              // CupertinoActionSheetAction(
              //   child: Row(
              //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //     children: [
              //       Row(
              //         children: [
              //           Icon(CupertinoIcons.person,
              //               size: 20, color: Color(0xFF007AFF)),
              //           SizedBox(width: 12),
              //           Text('Send Individually',
              //               style: TextStyle(fontSize: 16)),
              //         ],
              //       ),
              //       CupertinoSwitch(
              //         value: _sendAsIndividual,
              //         onChanged: (value) async {
              //           await _toggleSendType();
              //           setModalState(() {}); // Update modal UI
              //         },
              //       ),
              //     ],
              //   ),
              //   onPressed: () {},
              // ),
              // 2. Search
              CupertinoActionSheetAction(
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.search,
                        size: 20, color: Color(0xFF007AFF)),
                    SizedBox(width: 12),
                    Text('Search', style: TextStyle(fontSize: 16)),
                  ],
                ),
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _showSearchBar = true;
                  });
                },
              ),
            // 3. Insert Template
            CupertinoActionSheetAction(
              child: const Row(
                children: [
                  Icon(CupertinoIcons.doc_text,
                      size: 20, color: Color(0xFF007AFF)),
                  SizedBox(width: 12),
                  Text('Templates', style: TextStyle(fontSize: 16)),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _showTemplateList();
              },
            ),
            // 4. Share Group Contacts (only for groups)
            if (widget.conversation.contacts.length > 1)
              CupertinoActionSheetAction(
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.share,
                        size: 20, color: Color(0xFF007AFF)),
                    SizedBox(width: 12),
                    Text('Share Group Contacts',
                        style: TextStyle(fontSize: 16)),
                  ],
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _shareGroupContacts();
                },
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  void _showTemplateList() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Templates'),
        actions: [
          // Create Template link at the top
          CupertinoActionSheetAction(
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.add_circled,
                    size: 20, color: Color(0xFF007AFF)),
                SizedBox(width: 8),
                Text('Create Template',
                    style: TextStyle(fontSize: 16, color: Color(0xFF007AFF))),
              ],
            ),
            onPressed: () {
              Navigator.pop(context);
              _navigateToCreateTemplate();
            },
          ),
          // Existing templates
          ...widget.templates.map((template) {
            return CupertinoActionSheetAction(
              child: Text(template.name),
              onPressed: () {
                Navigator.pop(context);
                _insertTemplate(template);
              },
            );
          }),
          // Template Variables directly in the menu
          CupertinoActionSheetAction(
            child: const Text('[First Name]',
                style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () {
              Navigator.pop(context);
              _insertVariable('[First Name]');
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('[Last Name]',
                style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () {
              Navigator.pop(context);
              _insertVariable('[Last Name]');
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('[Full Name]',
                style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () {
              Navigator.pop(context);
              _insertVariable('[Full Name]');
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('[Phone]',
                style: TextStyle(color: Color(0xFF8E8E93))),
            onPressed: () {
              Navigator.pop(context);
              _insertVariable('[Phone]');
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _navigateToCreateTemplate() async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => const CreateTemplateScreen(),
      ),
    );

    if (result != null && result is MessageTemplate) {
      // Save the new template to storage
      widget.templates.add(result);
      await StorageService.saveTemplates(widget.templates);

      // Refresh UI
      setState(() {});

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "${result.name}" created'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _insertVariable(String variable) {
    final currentText = _messageController.text;
    final cursorPosition = _messageController.selection.baseOffset;

    final newText = currentText.substring(0, cursorPosition) +
        variable +
        currentText.substring(cursorPosition);

    _messageController.text = newText;
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: cursorPosition + variable.length),
    );
  }

  void _insertTemplate(MessageTemplate template) {
    final currentText = _messageController.text;
    final cursorPosition = _messageController.selection.baseOffset;

    // If cursor position is invalid (e.g., -1), insert at the end
    final safeCursorPosition =
        cursorPosition >= 0 ? cursorPosition : currentText.length;

    final newText = currentText.substring(0, safeCursorPosition) +
        template.content +
        currentText.substring(safeCursorPosition);

    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(
      offset: safeCursorPosition + template.content.length,
    );
  }

  /* void _showVariableErrorDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cannot Send Group Message'),
        content: const Text(
          'Your message contains variables (like [First Name]). Variables can only be used with individual messages.\n\nPlease enable "Send Individually" to use variables.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('Send Individually'),
            onPressed: () async {
              Navigator.pop(context);
              // COMMENTED OUT FOR RELEASE - NO TOGGLE NEEDED
              // await _toggleSendType(); // Switch to individual mode
              _sendMessage(); // Try sending again
            },
          ),
        ],
      ),
    );
  } */

  void _showExpiredMessageOptions(Message message) {
    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: CupertinoActionSheet(
          title: const Text('Message Options'),
          message: const Text('Message history has expired (1 week)'),
          actions: [
            // Copy
            CupertinoActionSheetAction(
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.doc_on_doc, size: 20),
                  SizedBox(width: 8),
                  Text('Copy'),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _copyMessage(message);
              },
            ),
            // Delete
            CupertinoActionSheetAction(
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  void _showMessageOptions(Message message) {
    // Check if message history has expired (1 week)
    final isHistoryExpired = message.historyExpiry != null &&
        DateTime.now().isAfter(message.historyExpiry!);

    if (isHistoryExpired) {
      // Show limited options for expired messages
      _showExpiredMessageOptions(message);
      return;
    }

    // Check if unsend is available (sent within last 5 minutes)
    final canUnsend = message.status == MessageStatus.sent &&
        DateTime.now().difference(message.timestamp).inMinutes < 5;

    showCupertinoModalPopup(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: CupertinoActionSheet(
          actions: [
            // 1. Edit
            CupertinoActionSheetAction(
              child: const Row(
                children: [
                  Icon(CupertinoIcons.pencil,
                      size: 20, color: Color(0xFF007AFF)),
                  SizedBox(width: 12),
                  Text('Edit', style: TextStyle(fontSize: 16)),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _startEditingMessage(message);
              },
            ),
            // 2. Unsend (only for sent messages within 5 minutes)
            if (canUnsend)
              CupertinoActionSheetAction(
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.arrow_uturn_left,
                        size: 20, color: Color(0xFFFF9500)),
                    SizedBox(width: 12),
                    Text('Unsend',
                        style:
                            TextStyle(fontSize: 16, color: Color(0xFFFF9500))),
                  ],
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _unsendMessage(message);
                },
              ),
            // 3. Delete
            CupertinoActionSheetAction(
              child: const Row(
                children: [
                  Icon(CupertinoIcons.trash,
                      size: 20, color: Color(0xFFFF3B30)),
                  SizedBox(width: 12),
                  Text('Delete',
                      style: TextStyle(fontSize: 16, color: Color(0xFFFF3B30))),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _deleteMessage(message);
              },
            ),
            // 3. Status (only if history hasn't expired)
            if (!isHistoryExpired)
              CupertinoActionSheetAction(
                child: const Row(
                  children: [
                    Icon(CupertinoIcons.checkmark_shield,
                        size: 20, color: Color(0xFF007AFF)),
                    SizedBox(width: 12),
                    Text('Status', style: TextStyle(fontSize: 16)),
                  ],
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showRecipients(message);
                },
              ),
            // 4. Copy
            CupertinoActionSheetAction(
              child: const Row(
                children: [
                  Icon(CupertinoIcons.doc_on_doc,
                      size: 20, color: Color(0xFF007AFF)),
                  SizedBox(width: 12),
                  Text('Copy', style: TextStyle(fontSize: 16)),
                ],
              ),
              onPressed: () {
                Navigator.pop(context);
                _copyMessage(message);
              },
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
    );
  }

  void _startEditingMessage(Message message) {
    // Save the current draft from the message input box
    _savedDraftDuringEdit = _messageController.text;

    setState(() {
      _editingMessageId = message.id;
      _editController.text = message.content;
    });

    // Calculate actual position after build using RenderBox
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messageKey = _messageKeys[message.id];
      if (messageKey?.currentContext != null) {
        try {
          final RenderBox renderBox =
              messageKey!.currentContext!.findRenderObject() as RenderBox;
          final position = renderBox.localToGlobal(Offset.zero);
          final screenHeight = MediaQuery.of(context).size.height;

          // Use the actual Y position of the message on screen
          final yRatio = (position.dy / screenHeight).clamp(0.1, 0.8);

          if (mounted) {
            setState(() {
              _editingBubbleYPosition = yRatio;
            });
          }

          Logger.info(
              'Edit position: actualY=${position.dy}, screenHeight=$screenHeight, ratio=$yRatio');
        } catch (e) {
          Logger.error('Error getting message position', e);
        }
      }
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editController.clear();
      // Restore the saved draft to the message input box
      if (_savedDraftDuringEdit != null) {
        _messageController.text = _savedDraftDuringEdit!;
        _savedDraftDuringEdit = null;
      }
    });
  }

  void _saveEditedMessage(Message message) async {
    final newContent = _editController.text.trim();
    if (newContent.isEmpty) {
      _cancelEditing();
      return;
    }

    // Cancel editing first
    setState(() {
      _editingMessageId = null;
      _editController.clear();
      // Restore the saved draft to the message input box
      if (_savedDraftDuringEdit != null) {
        _messageController.text = _savedDraftDuringEdit!;
        _savedDraftDuringEdit = null;
      }
    });

    // Send the new message without affecting the original message
    final allContactMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);
    _sendEditedMessageToAllMethods(allContactMethods, newContent);
  }

  void _deleteMessage(Message message) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF3B30))),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        widget.conversation.messages.removeWhere((m) => m.id == message.id);
      });

      // Remove from storage
      final messages = await StorageService.loadMessages();
      messages.removeWhere((m) => m.id == message.id);
      await StorageService.saveMessages(messages);
    }
  }

  void _unsendMessage(Message message) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Unsend Message'),
        content: const Text(
            'This will delete the message for all recipients. Continue?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            child: const Text('Unsend',
                style: TextStyle(color: Color(0xFFFF9500))),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        widget.conversation.messages.removeWhere((m) => m.id == message.id);
      });

      // Remove from storage
      final messages = await StorageService.loadMessages();
      messages.removeWhere((m) => m.id == message.id);
      await StorageService.saveMessages(messages);

      // Show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message unsent'),
            backgroundColor: Color(0xFFFF9500),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(top: 100, left: 16, right: 16),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showRecipients(Message message) async {
    // Get the latest message status from storage
    final messages = await StorageService.loadMessages();
    final latestMessage = messages.firstWhere(
      (m) => m.id == message.id,
      orElse: () => message,
    );

    // Get all contact methods from conversation
    final allContactMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);

    if (mounted) {
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => RecipientsScreen(
            message: latestMessage,
            allContactMethods: allContactMethods,
            originalRecipients: _messageOriginalRecipients[message.id],
            recipientStatuses: _recipientStatuses[message.id],
            onRetryRecipient: _retryMessageToRecipient,
            onRecipientAction: _showRetryOrGoToOption,
            onSendToNew: _sendToNewRecipient,
            onStatusUpdate: () {
              // Refresh message statuses when actions are performed
              if (mounted) {
                _refreshMessageStatuses();
              }
            },
            getRecipientStatuses: (messageId) => _recipientStatuses[messageId],
          ),
        ),
      );
    }
  }

  /* String _getMessageStatusForRecipient(Message message, ContactInfo method) {
    // Check message's recipient history first (persistent across group changes)
    final recipientKey = '${method.contact.displayName}_${method.value}';
    final status = message.recipientHistory[recipientKey];
    if (status != null) {
      return status;
    }

    // Fallback to old static map for backward compatibility
    final oldStatus = _recipientStatuses[message.id]?[recipientKey];
    if (oldStatus != null) {
      return oldStatus;
    }

    // Check if contact is on server (only server contacts can have verified status)
    final isOnServer = ServerService.isContactOnServer(method.contact);

    // For non-server contacts, we can't verify SMS/iMessage delivery
    // If no specific status found, default to "SMS" (gray) indicating we sent it via native SMS
    if (!isOnServer) {
      return 'SMS';
    }

    // For server contacts without individual status, we need to set a default
    // Don't fall back to overall message status as it can be misleading during retries
    Logger.warning(
        'No individual status found for ${method.contact.displayName}, defaulting to Failed');
    return 'Failed'; // Default to failed if no individual status is set
  } */

  Future<void> _updateRecipientStatus(
      String messageId, ContactInfo method, String status) async {
    final recipientKey = '${method.contact.displayName}_${method.value}';
    // Update message's recipient history (persistent)
    final message = widget.conversation.messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw Exception('Message not found: $messageId'),
    );

    message.recipientHistory[recipientKey] = status;

    // Also update old static map for backward compatibility
    if (_recipientStatuses[messageId] == null) {
      _recipientStatuses[messageId] = {};
    }
    _recipientStatuses[messageId]![recipientKey] = status;

    // Save the updated message and wait for it to complete
    await _saveMessage(message);
  }

  Future<void> _saveMessage(Message message) async {
    try {
      // Update the message in the conversation
      final index =
          widget.conversation.messages.indexWhere((m) => m.id == message.id);
      if (index != -1) {
        widget.conversation.messages[index] = message;
      }

      // Save to storage
      await StorageService.saveMessages(widget.conversation.messages);
      Logger.success('Updated message in storage: ${message.id}');
    } catch (e) {
      Logger.error('Error saving message', e);
    }
  }

  bool _hasAnyFailedRecipients(String messageId) {
    // Get all contact methods for the conversation
    final allMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);

    // Check if any recipient has failed or cancelled status
    for (var method in allMethods) {
      final recipientKey = '${method.contact.displayName}_${method.value}';
      final status = _recipientStatuses[messageId]?[recipientKey];

      // Check both server and non-server users for failed/cancelled status
      if (status == 'Failed' || status == 'Cancelled') {
        return true;
      }
    }

    return false;
  }

  /* Widget _buildRecipientStatusBadge(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'Sending':
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.clock;
        break;
      case 'Sent':
        color = const Color(0xFF34C759);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'SMS':
        color = const Color(0xFF8E8E93); // Gray for SMS (unverified)
        icon = CupertinoIcons.checkmark_circle;
        break;
      case 'New Recipient':
        color = const Color(0xFF8E8E93); // Gray for new recipient
        icon = CupertinoIcons.person_badge_plus;
        break;
      case 'Delivered':
        color = const Color(0xFF5AC8FA); // Light blue for delivered
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Read':
        color = const Color(0xFF007AFF);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Failed':
        color = const Color(0xFFFF3B30);
        icon = CupertinoIcons.exclamationmark_circle_fill;
        break;
      default:
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  } */

  void _copyMessage(Message message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        backgroundColor: Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(top: 100, left: 16, right: 16),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRetryOrGoToOption(ContactInfo method, String content,
      bool isOnServer, Message message, Function() onUpdate) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(isOnServer ? 'Message Failed' : 'Open Conversation'),
        content: Text(
          isOnServer
              ? 'Retry sending to ${method.contact.displayName ?? 'this contact'}?'
              : 'Open Messages app to view conversation with ${method.contact.displayName ?? 'this contact'}?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: Text(isOnServer ? 'Retry' : 'Go to'),
            onPressed: () {
              Navigator.pop(context);
              if (isOnServer) {
                _retryMessageToRecipient(method, content, message, onUpdate);
              } else {
                _goToNativeMessagesApp(method, content);
              }
            },
          ),
        ],
      ),
    );
  }

  void _retryMessageToRecipient(ContactInfo method, String content,
      Message message, Function() onUpdate) async {
    if (message.type == MessageType.group) {
      // For group messages, retry the entire message to the server
      _retryGroupMessage(message, onUpdate);
    } else {
      // For individual messages, retry just this recipient
      _retryIndividualRecipient(method, content, message, onUpdate);
    }
  }

  Future<void> _retryGroupMessage(Message message, Function() onUpdate) async {
    // Since we're treating all users as non-server users, retry each recipient individually
    final allMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);

    for (var method in allMethods) {
      // Update status to sending
      await _updateRecipientStatus(message.id, method, 'Sending');
    }
    onUpdate();

    // Send to each recipient individually (same as original send logic)
    for (var method in allMethods) {
      if (method.type == ContactInfoType.phone) {
        final smsStatus = await _sendSMSWithStatusDetection(
          message.content,
          [method.value],
          method.contact,
        );

        if (smsStatus == 'sent') {
          await _updateRecipientStatus(message.id, method, 'SMS');
        } else if (smsStatus == 'cancelled') {
          await _updateRecipientStatus(message.id, method, 'Cancelled');
        }
      } else if (method.type == ContactInfoType.email) {
        final emailStatus = await _sendEmailWithStatusDetection(
          message.content,
          method.value,
          method.contact,
        );

        if (emailStatus == 'sent') {
          await _updateRecipientStatus(message.id, method, 'Email');
        } else if (emailStatus == 'cancelled') {
          await _updateRecipientStatus(message.id, method, 'Cancelled');
        }
      }

      // Small delay between sends
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Update overall message status
    final hasFailures = _hasAnyFailedRecipients(message.id);
    final newStatus = hasFailures ? MessageStatus.failed : MessageStatus.sent;

    // Update the message status in memory (recipientHistory was already saved by _updateRecipientStatus)
    final messageIndex =
        widget.conversation.messages.indexWhere((m) => m.id == message.id);
    if (messageIndex != -1) {
      widget.conversation.messages[messageIndex].status = newStatus;
    }

    // Update UI
    if (mounted) {
      setState(() {});
    }

    onUpdate();
  }

  Future<void> _retryIndividualRecipient(ContactInfo method, String content,
      Message message, Function() onUpdate) async {
    // Update status to sending
    await _updateRecipientStatus(message.id, method, 'Sending');
    onUpdate();

    // Actually retry by sending again
    if (method.type == ContactInfoType.phone) {
      final smsStatus = await _sendSMSWithStatusDetection(
        content,
        [method.value],
        method.contact,
      );

      if (smsStatus == 'sent') {
        await _updateRecipientStatus(message.id, method, 'SMS');
        Logger.success('Retry successful: SMS sent');
      } else if (smsStatus == 'cancelled') {
        await _updateRecipientStatus(message.id, method, 'Cancelled');
        Logger.warning('Retry cancelled: SMS cancelled');
      }
    } else if (method.type == ContactInfoType.email) {
      final emailStatus = await _sendEmailWithStatusDetection(
        content,
        method.value,
        method.contact,
      );

      if (emailStatus == 'sent') {
        await _updateRecipientStatus(message.id, method, 'Email');
        Logger.success('Retry successful: Email sent');
      } else if (emailStatus == 'cancelled') {
        await _updateRecipientStatus(message.id, method, 'Cancelled');
        Logger.warning('Retry cancelled: Email cancelled');
      }
    } else {
      // For other methods, simulate success
      await _updateRecipientStatus(message.id, method, 'Sent');
    }

    // Check if ALL recipients are now successful and update message status
    final hasFailures = _hasAnyFailedRecipients(message.id);
    final newStatus = hasFailures ? MessageStatus.failed : MessageStatus.sent;

    // Update the message status in memory (recipientHistory was already saved by _updateRecipientStatus)
    final messageIndex =
        widget.conversation.messages.indexWhere((m) => m.id == message.id);
    if (messageIndex != -1) {
      widget.conversation.messages[messageIndex].status = newStatus;
    }

    // Update UI
    if (mounted) {
      setState(() {});
    }

    // Notify parent to refresh
    onUpdate();
  }

  /* Future<void> _simulateGroupMessageDelivery(Message message) async {
    // Simulate individual delivery to each recipient
    final allMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);

    for (var method in allMethods) {
      // Simulate delivery delay
      await Future.delayed(const Duration(milliseconds: 200));

      // Simulate delivery success (80% success rate)
      final delivered = DateTime.now().millisecond % 10 < 8;

      if (delivered) {
        // Simulate read receipt (60% read rate)
        await Future.delayed(const Duration(milliseconds: 500));
        final read = DateTime.now().millisecond % 10 < 6;
        await _updateRecipientStatus(
            message.id, method, read ? 'Read' : 'Delivered');
      } else {
        await _updateRecipientStatus(message.id, method, 'Failed');
      }
    }
  } */

  Future<void> _goToNativeMessagesApp(
      ContactInfo method, String content) async {
    if (method.type == ContactInfoType.phone) {
      // Just open the conversation, don't pre-populate message
      final smsUrl = 'sms:${method.value}';
      try {
        await launchUrl(Uri.parse(smsUrl));
      } catch (e) {
        Logger.error('Error opening native Messages app', e);
      }
    }
  }

  void _sendToNewRecipient(
      ContactInfo method, Message message, Function() onUpdate) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Send to New Recipient'),
        content: Text(
          'Send this message to ${method.contact.displayName ?? 'this contact'}?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            child: const Text('Send'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Add to original recipients
    final recipientKey = '${method.contact.displayName}_${method.value}';
    if (_messageOriginalRecipients[message.id] == null) {
      _messageOriginalRecipients[message.id] = {};
    }
    _messageOriginalRecipients[message.id]!.add(recipientKey);

    // Check if contact is on server
    final isOnServer = ServerService.isContactOnServer(method.contact);

    if (isOnServer) {
      // Update status to sending
      await _updateRecipientStatus(message.id, method, 'Sending');
      onUpdate();

      // Simulate sending
      await Future.delayed(const Duration(seconds: 1));

      // Random status for server users (50% failure for testing)
      final random = DateTime.now().microsecond % 100;
      String status;
      if (random < 50) {
        status = 'Failed';
      } else if (random < 80) {
        status = 'Sent';
      } else {
        status = 'Delivered';
      }

      await _updateRecipientStatus(message.id, method, status);

      // Check if ALL recipients are now successful
      final hasFailures = _hasAnyFailedRecipients(message.id);
      final newStatus = hasFailures ? MessageStatus.failed : MessageStatus.sent;

      // Update message status in storage
      final updatedMessage = Message(
        id: message.id,
        content: message.content,
        timestamp: message.timestamp,
        isFromMe: message.isFromMe,
        contactId: message.contactId,
        groupId: message.groupId,
        status: newStatus,
        type: message.type,
        recipientHistory: message.recipientHistory,
        historyExpiry: message.historyExpiry,
        originalRecipients: message.originalRecipients,
      );

      await _updateMessageInStorage(updatedMessage);

      // Update UI
      if (mounted) {
        setState(() {
          final messageIndex = widget.conversation.messages
              .indexWhere((m) => m.id == message.id);
          if (messageIndex != -1) {
            widget.conversation.messages[messageIndex] = updatedMessage;
          }
        });
      }

      onUpdate();
    } else {
      // Send via SMS or Email for non-server users
      if (method.type == ContactInfoType.phone) {
        final smsStatus = await _sendSMSWithStatusDetection(
          message.content,
          [method.value],
          method.contact,
        );

        if (smsStatus == 'sent') {
          // Non-server users show as SMS
          await _updateRecipientStatus(message.id, method, 'SMS');
          onUpdate();
        } else if (smsStatus == 'cancelled') {
          // Mark as cancelled
          await _updateRecipientStatus(message.id, method, 'Cancelled');
          onUpdate();
        }
      } else if (method.type == ContactInfoType.email) {
        final emailStatus = await _sendEmailWithStatusDetection(
          message.content,
          method.value,
          method.contact,
        );

        if (emailStatus == 'sent') {
          // Non-server users show as Email
          await _updateRecipientStatus(message.id, method, 'Email');
          onUpdate();
        } else if (emailStatus == 'cancelled') {
          // Mark as cancelled
          await _updateRecipientStatus(message.id, method, 'Cancelled');
          onUpdate();
        }
      }
    }
  }

  /* void _showNonServerWarning(List<Contact> nonServerContacts, String content) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Native Contacts Detected'),
        content: Text(
          'Some contacts (${nonServerContacts.map((c) => c.displayName).join(', ')}) are not on the server and can only receive individual messages. Would you like to send individual messages to them via the native Messages app?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('Send Individual'),
            onPressed: () {
              Navigator.pop(context);
              _sendIndividualToNative(nonServerContacts, content);
            },
          ),
        ],
      ),
    );
  } */

  /* void _sendIndividualToNative(List<Contact> contacts, String content) async {
    for (final contact in contacts) {
      if (contact.phones?.isNotEmpty == true) {
        final phoneNumber = contact.phones!.first.value;

        // Skip if phone number is null
        if (phoneNumber == null) continue;

        try {
          // Use flutter_sms to open native SMS composer with pre-filled recipient and message
          await sendSMS(
            message: content,
            recipients: [phoneNumber],
          );
        } catch (e) {
          Logger.error('Error sending SMS to $phoneNumber', e);
          // Fallback to URL scheme if flutter_sms fails
          final smsUrl =
              'sms:$phoneNumber?body=${Uri.encodeComponent(content)}';
          launchUrl(Uri.parse(smsUrl));
        }
      }
    }

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Opening native Messages app for ${contacts.length} contact(s)'),
        backgroundColor: const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
        duration: const Duration(seconds: 2),
      ),
    );
  } */

  void _sendMessage() {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    // COMMENTED OUT FOR RELEASE - ALWAYS SENDING INDIVIDUALLY
    // Check if trying to send group message with variables
    // if (!_sendAsIndividual && Helpers.hasVariables(content)) {
    //   _showVariableErrorDialog();
    //   return;
    // }

    // Get all contact methods from the conversation
    final allContactMethods =
        Helpers.extractContactMethods(widget.conversation.contacts);

    Logger.info('Total contact methods: ${allContactMethods.length}');
    for (var method in allContactMethods) {
      Logger.info(
          '  - ${method.contact.displayName}: ${method.displayValue} (${method.displayLabel})');
    }

    // COMMENTED OUT FOR RELEASE - ALL CONTACTS ARE NATIVE SMS
    // Check for non-server contacts
    // final nonServerContacts = widget.conversation.contacts
    //     .where((contact) => !ServerService.isContactOnServer(contact))
    //     .toList();

    // FOR RELEASE: Always send individually
    _sendIndividualToAllMethods(allContactMethods, content);

    _messageController.clear();
    _currentDraft = '';
    _saveDraftForConversation(widget.conversation.id, ''); // Clear draft

    // Scroll to bottom immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // COMMENTED OUT FOR RELEASE - HANDLED IN _sendIndividualToAllMethods
    // Track original recipients for this message
    // _trackOriginalRecipients(message.id, allContactMethods);

    // Save message to storage
    // _saveMessageToStorage(message);

    // Simulate sending the message
    // _simulateMessageSending(message);
  }

  void _trackOriginalRecipients(
      String messageId, List<ContactInfo> contactMethods) {
    final recipientKeys = contactMethods.map((method) {
      return '${method.contact.displayName}_${method.value}';
    }).toSet();
    _messageOriginalRecipients[messageId] = recipientKeys;
  }

  // Send individual message to each contact method
  void _sendIndividualToAllMethods(
      List<ContactInfo> contactMethods, String content) async {
    // Use all contact methods (phones and emails)
    final allMethods = contactMethods;

    // Create original recipients list
    final originalRecipients = allMethods
        .map((method) => RecipientInfo.fromContactInfo(
            method, method.type == ContactInfoType.phone ? 'phone' : 'email'))
        .toList();

    // Create ONE message in the UI (marked as individual type)
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      timestamp: DateTime.now(),
      isFromMe: true,
      groupId: widget.conversation.id,
      status: MessageStatus.sending,
      type: MessageType.individual,
      historyExpiry:
          DateTime.now().add(const Duration(days: 7)), // 1 week expiry
      originalRecipients: originalRecipients,
    );

    // Initialize recipient history with "Sending" status for all recipients
    for (var method in allMethods) {
      final recipientKey = '${method.contact.displayName}_${method.value}';
      message.recipientHistory[recipientKey] = 'Sending';
    }

    // Navigate to status screen BEFORE sending (for groups with 2+ contacts)
    if (allMethods.length > 1) {
      // Add message to UI first so status screen can display it
      setState(() {
        widget.conversation.messages.add(message);
        widget.conversation.lastMessageTime = message.timestamp;
        widget.conversation.lastMessagePreview = message.content;
      });

      // Track original recipients for this message
      _trackOriginalRecipients(message.id, allMethods);

      // Save to storage
      await _saveMessageToStorage(message);

      // Navigate to status screen immediately
      _showRecipients(message);
    }

    // Add to conversation UI (only if not already added for groups)
    if (allMethods.length <= 1) {
      setState(() {
        widget.conversation.messages.add(message);
        widget.conversation.lastMessageTime = message.timestamp;
        widget.conversation.lastMessagePreview = message.content;
      });

      // Track original recipients for this message
      _trackOriginalRecipients(message.id, allMethods);

      // Save to storage
      await _saveMessageToStorage(message);
    }

    // Clear input
    _messageController.clear();
    _currentDraft = '';
    _saveDraftForConversation(widget.conversation.id, '');

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    Logger.info(
        'Sending individual messages to ${allMethods.length} contact methods');

    // Send to each contact method individually and set per-recipient status
    int successCount = 0;
    int failCount = 0;
    bool shouldStop = false;

    for (var method in allMethods) {
      if (shouldStop) break;

      Logger.info(
          'Sending to: ${method.displayValue} (${method.contact.displayName})');

      // Check if contact is on server
      final isOnServer = ServerService.isContactOnServer(method.contact);

      if (isOnServer) {
        // For server users, simulate realistic delivery status (50% failure for testing)
        // Failed: 50%, Sent: 30%, Delivered: 15%, Sending: 5%
        final random = DateTime.now().microsecond % 100;
        String status;
        if (random < 50) {
          status = 'Failed';
          failCount++;
        } else if (random < 55) {
          status = 'Sending';
          successCount++;
        } else if (random < 85) {
          status = 'Sent';
          successCount++;
        } else {
          status = 'Delivered';
          successCount++;
        }
        await _updateRecipientStatus(message.id, method, status);
        Logger.info('   → Server user: $status');
      } else {
        // For non-server users, set initial "Sending" status
        await _updateRecipientStatus(message.id, method, 'Sending');

        if (method.type == ContactInfoType.phone) {
          // Send via SMS
          final smsStatus = await _sendSMSWithStatusDetection(
            content,
            [method.value],
            method.contact,
          );

          if (smsStatus == 'sent') {
            successCount++;
            await _updateRecipientStatus(message.id, method, 'SMS');
            Logger.success('   → Non-server user: SMS sent');
          } else if (smsStatus == 'cancelled') {
            Logger.warning('   → Non-server user: SMS cancelled');
            await _updateRecipientStatus(message.id, method, 'Cancelled');
            failCount++;

            // Show popup for cancellation
            if (mounted) {
              shouldStop = await _showCancelConfirmationDialog();
            }
          }
        } else if (method.type == ContactInfoType.email) {
          // Send via Email
          final emailStatus = await _sendEmailWithStatusDetection(
            content,
            method.value,
            method.contact,
          );

          if (emailStatus == 'sent') {
            successCount++;
            await _updateRecipientStatus(message.id, method, 'Email');
            Logger.success('   → Non-server user: Email sent');
          } else if (emailStatus == 'cancelled') {
            Logger.warning('   → Non-server user: Email cancelled');
            await _updateRecipientStatus(message.id, method, 'Cancelled');
            failCount++;

            // Show popup for cancellation
            if (mounted) {
              shouldStop = await _showCancelConfirmationDialog();
            }
          }
        }
      }

      // Small delay to vary the microsecond random seed
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // Update message status based on results
    // If ANY recipient failed, show as failed
    final updatedStatus =
        failCount > 0 ? MessageStatus.failed : MessageStatus.sent;

    final updatedMessage = Message(
      id: message.id,
      content: message.content,
      timestamp: message.timestamp,
      isFromMe: message.isFromMe,
      contactId: message.contactId,
      groupId: message.groupId,
      status: updatedStatus,
      type: message.type,
      recipientHistory: message.recipientHistory,
      historyExpiry: message.historyExpiry,
      originalRecipients: message.originalRecipients,
    );

    // Update in UI and storage
    if (mounted) {
      setState(() {
        final messageIndex =
            widget.conversation.messages.indexWhere((m) => m.id == message.id);
        if (messageIndex != -1) {
          widget.conversation.messages[messageIndex] = updatedMessage;
        }
      });
    }

    await _updateMessageInStorage(updatedMessage);

    // Show success message (only for single recipients)
    if (allMethods.length <= 1 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Sent to $successCount of ${allMethods.length} contact(s)'),
          backgroundColor: failCount == 0
              ? const Color(0xFF34C759)
              : const Color(0xFFFF9500),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    // For groups, status screen is already shown before sending
  }

  // Send edited message to all contact methods (creates new message without affecting original)
  void _sendEditedMessageToAllMethods(
      List<ContactInfo> contactMethods, String content) async {
    // Use all contact methods (phones and emails)
    final allMethods = contactMethods;

    // Create original recipients list
    final originalRecipients = allMethods
        .map((method) => RecipientInfo.fromContactInfo(
            method, method.type == ContactInfoType.phone ? 'phone' : 'email'))
        .toList();

    // Create a completely new message with new ID and timestamp
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      timestamp: DateTime.now(),
      isFromMe: true,
      groupId: widget.conversation.id,
      status: MessageStatus.sending,
      type: MessageType.individual,
      historyExpiry:
          DateTime.now().add(const Duration(days: 7)), // 1 week expiry
      originalRecipients: originalRecipients,
    );

    // Initialize recipient history with "Sending" status for all recipients
    for (var method in allMethods) {
      final recipientKey = '${method.contact.displayName}_${method.value}';
      message.recipientHistory[recipientKey] = 'Sending';
    }

    // Navigate to status screen BEFORE sending (for groups with 2+ contacts)
    if (allMethods.length > 1) {
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => RecipientsScreen(
            message: message,
            allContactMethods: allMethods,
            originalRecipients: null, // No original recipients for new message
            recipientStatuses: const {},
            onRetryRecipient: _retryMessageToRecipient,
            onRecipientAction: _showRetryOrGoToOption,
            onSendToNew: _sendToNewRecipient,
            onStatusUpdate: () {
              _refreshMessageStatuses();
            },
            getRecipientStatuses: (messageId) => _recipientStatuses[messageId],
          ),
        ),
      );
    }

    // Add to conversation UI
    setState(() {
      widget.conversation.messages.add(message);
      widget.conversation.lastMessageTime = message.timestamp;
    });

    // Save to storage
    await _saveMessageToStorage(message);

    // Track original recipients for this message
    _trackOriginalRecipients(message.id, allMethods);

    // Send to each contact method
    int successCount = 0;
    int failCount = 0;
    bool shouldStop = false;

    for (var method in allMethods) {
      if (shouldStop) break;

      Logger.info(
          'Sending to: ${method.displayValue} (${method.contact.displayName})');

      // For non-server users, set initial "Sending" status
      await _updateRecipientStatus(message.id, method, 'Sending');

      if (method.type == ContactInfoType.phone) {
        // Send via SMS
        final smsStatus = await _sendSMSWithStatusDetection(
          content,
          [method.value],
          method.contact,
        );

        if (smsStatus == 'sent') {
          successCount++;
          await _updateRecipientStatus(message.id, method, 'SMS');
          Logger.success('Non-server user: SMS sent');
        } else if (smsStatus == 'cancelled') {
          Logger.warning('Non-server user: SMS cancelled');
          await _updateRecipientStatus(message.id, method, 'Cancelled');
          failCount++;

          // Show popup for cancellation
          if (mounted) {
            shouldStop = await _showCancelConfirmationDialog();
          }
        }
      } else if (method.type == ContactInfoType.email) {
        // Send via Email
        final emailStatus = await _sendEmailWithStatusDetection(
          content,
          method.value,
          method.contact,
        );

        if (emailStatus == 'sent') {
          successCount++;
          await _updateRecipientStatus(message.id, method, 'Email');
          Logger.success('Non-server user: Email sent');
        } else if (emailStatus == 'cancelled') {
          Logger.warning('Non-server user: Email cancelled');
          await _updateRecipientStatus(message.id, method, 'Cancelled');
          failCount++;

          // Show popup for cancellation
          if (mounted) {
            shouldStop = await _showCancelConfirmationDialog();
          }
        }
      }

      // Small delay to vary the microsecond random seed
      await Future.delayed(const Duration(milliseconds: 10));
    }

    // Update message status based on results
    final newStatus = failCount > 0 ? MessageStatus.failed : MessageStatus.sent;
    final updatedMessage = Message(
      id: message.id,
      content: message.content,
      timestamp: message.timestamp,
      isFromMe: message.isFromMe,
      contactId: message.contactId,
      groupId: message.groupId,
      status: newStatus,
      type: message.type,
      recipientHistory: message.recipientHistory,
      historyExpiry: message.historyExpiry,
    );

    // Update in conversation
    setState(() {
      final messageIndex =
          widget.conversation.messages.indexWhere((m) => m.id == message.id);
      if (messageIndex != -1) {
        widget.conversation.messages[messageIndex] = updatedMessage;
      }
    });

    // Save updated message
    await _updateMessageInStorage(updatedMessage);

    // Show success message only for single recipients
    if (allMethods.length == 1 && successCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Message sent to ${allMethods.first.contact.displayName}'),
          backgroundColor: const Color(0xFF34C759),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Send individual messages to all (for group mode with non-server users)
  /* void _sendIndividualMessagesToAll(
      List<ContactInfo> contactMethods, String content) async {
    // Create ONE message in the UI (marked as GROUP type - sent individually behind the scenes)
    final message = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      timestamp: DateTime.now(),
      isFromMe: true,
      groupId: widget.conversation.id,
      status: MessageStatus.sending,
      type: MessageType.group, // Still group type, just sent individually
      historyExpiry:
          DateTime.now().add(const Duration(days: 7)), // 1 week expiry
    );

    // Add to conversation UI (only once)
    setState(() {
      widget.conversation.messages.add(message);
      widget.conversation.lastMessageTime = message.timestamp;
      widget.conversation.lastMessagePreview = message.content;
    });

    // Track original recipients for this message
    _trackOriginalRecipients(message.id, contactMethods);

    // Save to storage (only once)
    await _saveMessageToStorage(message);

    // Clear input
    _messageController.clear();
    _currentDraft = '';
    _saveDraftForConversation(widget.conversation.id, '');

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // Send to each contact method in the background
    for (var method in contactMethods) {
      if (method.type == ContactInfoType.phone) {
        if (ServerService.isContactOnServer(method.contact)) {
          // Server contacts handled via simulation
          // (would be API call in real app)
        } else {
          // Send via native SMS for non-server contacts
          try {
            await sendSMS(
              message: content,
              recipients: [method.value],
            );
          } catch (e) {
            Logger.error('Error sending SMS to ${method.value}', e);
          }
        }
      }
    }

    // Simulate sending for server contacts
    _simulateMessageSending(message);
  } */

  Future<void> _saveMessageToStorage(Message message) async {
    try {
      final messages = await StorageService.loadMessages();
      messages.add(message);
      await StorageService.saveMessages(messages);
      Logger.info('Saved message to storage: ${message.content}');
    } catch (e) {
      Logger.error('Error saving message', e);
    }
  }

  /* void _simulateMessageSending(Message message) async {
    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 2));

      // For group messages, set individual recipient statuses
      if (message.type == MessageType.group) {
        final allMethods =
            Helpers.extractContactMethods(widget.conversation.contacts);

        // Set individual statuses for each recipient
        for (var method in allMethods) {
          final isOnServer = ServerService.isContactOnServer(method.contact);
          if (isOnServer) {
            // Simulate different statuses for server users (50% failure for testing)
            final random = DateTime.now().microsecond % 100;
            String status;
            if (random < 50) {
              status = 'Failed';
            } else if (random < 80) {
              status = 'Sent';
            } else {
              status = 'Delivered';
            }
            await _updateRecipientStatus(message.id, method, status);
          } else {
            // Non-server users show as SMS
            await _updateRecipientStatus(message.id, method, 'SMS');
          }
        }

        // Check if any recipients failed
        final hasFailures = _hasAnyFailedRecipients(message.id);
        final newStatus =
            hasFailures ? MessageStatus.failed : MessageStatus.sent;

        // Update message status
        final updatedMessage = Message(
          id: message.id,
          content: message.content,
          timestamp: message.timestamp,
          isFromMe: message.isFromMe,
          contactId: message.contactId,
          groupId: message.groupId,
          status: newStatus,
          type: message.type,
        );

        // Always save to storage first (even if unmounted)
        await _updateMessageInStorage(updatedMessage);

        // Update the message in the conversation UI if still mounted
        if (mounted) {
          setState(() {
            final messageIndex = widget.conversation.messages
                .indexWhere((m) => m.id == message.id);
            if (messageIndex != -1) {
              widget.conversation.messages[messageIndex] = updatedMessage;
            }
          });
        }

        Logger.info(
            'Group message processed: ${message.content} (${hasFailures ? 'Failed' : 'Sent'})');
      } else {
        // For individual messages, use the old logic
        final success = DateTime.now().millisecond % 2 == 0;

      // Update message status
      final updatedMessage = Message(
        id: message.id,
        content: message.content,
        timestamp: message.timestamp,
        isFromMe: message.isFromMe,
        contactId: message.contactId,
        groupId: message.groupId,
        status: success ? MessageStatus.sent : MessageStatus.failed,
        type: message.type,
          recipientHistory: message.recipientHistory,
          historyExpiry: message.historyExpiry,
          originalRecipients: message.originalRecipients,
      );

      // Always save to storage first (even if unmounted)
      await _updateMessageInStorage(updatedMessage);

      // Update the message in the conversation UI if still mounted
      if (mounted) {
        setState(() {
          final messageIndex = widget.conversation.messages
              .indexWhere((m) => m.id == message.id);
          if (messageIndex != -1) {
            widget.conversation.messages[messageIndex] = updatedMessage;
          }
        });
      }

      if (!success) {
          Logger.error('Message failed to send: ${message.content}');
      } else {
          Logger.success('Message sent successfully: ${message.content}');
        }
      }
    } catch (e) {
      Logger.error('Error sending message', e);

      // Update message status to failed
      final failedMessage = Message(
        id: message.id,
        content: message.content,
        timestamp: message.timestamp,
        isFromMe: message.isFromMe,
        contactId: message.contactId,
        groupId: message.groupId,
        status: MessageStatus.failed,
        type: message.type,
        recipientHistory: message.recipientHistory,
        historyExpiry: message.historyExpiry,
        originalRecipients: message.originalRecipients,
      );

      // Always save to storage first
      await _updateMessageInStorage(failedMessage);

      if (mounted) {
        setState(() {
          final messageIndex = widget.conversation.messages
              .indexWhere((m) => m.id == message.id);
          if (messageIndex != -1) {
            widget.conversation.messages[messageIndex] = failedMessage;
          }
        });
      }
    }
  } */

  Future<void> _updateMessageInStorage(Message message) async {
    try {
      final messages = await StorageService.loadMessages();
      final messageIndex = messages.indexWhere((m) => m.id == message.id);
      if (messageIndex != -1) {
        messages[messageIndex] = message;
        await StorageService.saveMessages(messages);
        Logger.info('Updated message status in storage: ${message.status}');
      }
    } catch (e) {
      Logger.error('Error updating message in storage', e);
    }
  }

  void _showConversationInfo() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Conversation Info'),
            backgroundColor: const Color(0xFFF9F9F9),
            elevation: 0,
            actions: [
              if (widget.conversation.contacts.length > 1)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showRenameDialog();
                  },
                  child: const Text('Rename',
                      style: TextStyle(color: Color(0xFF007AFF))),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _editGroupMembers();
                },
                child: const Text('Edit',
                    style: TextStyle(color: Color(0xFF007AFF))),
              ),
            ],
          ),
          body: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFFF9F9F9),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.person_2,
                      color: Color(0xFF007AFF),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${widget.conversation.contacts.length} Recipients',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Contact list grouped by contact - uses same widget as edit screen
              Expanded(
                child: ListView.builder(
                  itemCount: widget.conversation.contacts.length,
                  itemBuilder: (context, index) {
                    final contact = widget.conversation.contacts[index];
                    // Use ExpandableContactTile in display-only mode (no selection)
                    return ExpandableContactTile(
                      contact: contact,
                      selectedContactInfos: const {}, // Empty set - display only
                      onContactInfoToggle: (info, selected) {
                        // No-op - info screen is display only
                      },
                      showCheckboxes: false, // Hide checkboxes in info screen
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // COMMENTED OUT FOR RELEASE - NO BACKEND SERVER
  // void _sendInvite(ContactInfo method) async {
  //   final inviteMessage =
  //       'Join me on sendit! Download here: https://sendit.app/invite';

  //   if (method.type == ContactInfoType.phone) {
  //     // Open native Messages app with invite pre-filled
  //     final smsUrl =
  //         'sms:${method.value}&body=${Uri.encodeComponent(inviteMessage)}';
  //     try {
  //       await launchUrl(Uri.parse(smsUrl));
  //     } catch (e) {
  //       print('❌ Error opening Messages app: $e');
  //     }
  //   }
  // }

  void _showRenameDialog() {
    final nameController =
        TextEditingController(text: widget.conversation.name ?? '');

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Rename Group'),
        content: Column(
          children: [
            const Text('Enter a new name for this group'),
            const SizedBox(height: 16),
            CupertinoTextField(
              controller: nameController,
              placeholder: 'Group name',
              autofocus: true,
              maxLength: 50,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('Save'),
            onPressed: () {
              final newName = nameController.text.trim();
              _renameGroup(newName.isEmpty ? null : newName);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _renameGroup(String? newName) {
    setState(() {
      widget.conversation.name = newName;
    });

    // Update the group in storage
    _updateGroupInStorage();
  }

  Future<void> _updateGroupInStorage() async {
    try {
      final groups = await StorageService.loadGroups();
      final groupIndex =
          groups.indexWhere((g) => g.id == widget.conversation.id);
      if (groupIndex != -1) {
        groups[groupIndex] = ContactGroup(
          id: widget.conversation.id,
          name: widget.conversation.name ?? '',
          contacts: widget.conversation.contacts,
        );
        await StorageService.saveGroups(groups);
        Logger.info('Updated group in storage');
      }
    } catch (e) {
      Logger.error('Error updating group', e);
    }
  }

  void _editGroupMembers() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => EditGroupMembersScreen(
          conversation: widget.conversation,
          onMembersUpdated: (updatedContacts) {
            setState(() {
              widget.conversation.contacts = updatedContacts;
            });
            _updateGroupInStorage();
          },
        ),
      ),
    );
  }

  // Build conversation avatar for AppBar
  Widget _buildConversationAvatar() {
    final avatarColor = _getAvatarColor(widget.conversation.id);

    if (widget.conversation.contacts.isEmpty) {
      // Empty group
      return const CircleAvatar(
        backgroundColor: Color(0xFF8E8E93),
        child: Icon(
          CupertinoIcons.person_add,
          color: Colors.white,
          size: 20,
        ),
      );
    } else if (widget.conversation.contacts.length == 1) {
      // Single contact
      final contact = widget.conversation.contacts.first;
      return CircleAvatar(
        backgroundColor: avatarColor,
        child: Text(
          (contact.displayName?.isNotEmpty == true
                  ? contact.displayName![0]
                  : '?')
              .toUpperCase(),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      // Group - show count of contacts
      return CircleAvatar(
        backgroundColor: avatarColor,
        child: Text(
          '${widget.conversation.contacts.length}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: widget.conversation.contacts.length > 99 ? 12 : 16,
          ),
        ),
      );
    }
  }

  // Helper method to get avatar color based on conversation ID
  Color _getAvatarColor(String id) {
    final colors = [
      const Color(0xFF007AFF),
      const Color(0xFF34C759),
      const Color(0xFFFF9500),
      const Color(0xFFFF3B30),
      const Color(0xFF5856D6),
      const Color(0xFFFF2D92),
      const Color(0xFF5AC8FA),
      const Color(0xFFFFCC00),
    ];

    // Use conversation ID to consistently pick a color
    final hash = id.hashCode;
    return colors[hash.abs() % colors.length];
  }

  // Helper method to replace template variables with contact information
  String _replaceTemplateVariables(String content, Contact contact) {
    String result = content;

    // Replace [First Name] with first name
    final firstName = contact.displayName?.split(' ').first ?? 'Unknown';
    result = result.replaceAll('[First Name]', firstName);

    // Replace [Last Name] with last name
    final lastName = (contact.displayName?.split(' ').length ?? 0) > 1
        ? contact.displayName!.split(' ').skip(1).join(' ')
        : '';
    result = result.replaceAll('[Last Name]', lastName);

    // Replace [Full Name] with full name
    final fullName = contact.displayName ?? 'Unknown';
    result = result.replaceAll('[Full Name]', fullName);

    // Replace [Phone] with first phone number
    final phone = contact.phones?.isNotEmpty == true
        ? contact.phones!.first.value ?? 'No phone'
        : 'No phone';
    result = result.replaceAll('[Phone]', phone);

    return result;
  }

  // Helper method to send SMS and detect cancellation
  Future<String> _sendSMSWithStatusDetection(
      String message, List<String> recipients, Contact contact) async {
    try {
      // Replace template variables with actual contact information
      final personalizedMessage = _replaceTemplateVariables(message, contact);

      Logger.info('Original message: $message');
      Logger.info(
          'Personalized for ${contact.displayName}: $personalizedMessage');

      // SIMPLIFIED APPROACH: Trust the native iOS MFMessageComposeViewController delegate
      // The flutter_sms package should properly handle the delegate methods

      // Send SMS and capture the result
      final result = await sendSMS(
        message: personalizedMessage,
        recipients: recipients,
      );

      Logger.info('SMS sendSMS result: $result (type: ${result.runtimeType})');

      // SIMPLE DETECTION: Only check return value
      // The native iOS implementation should return appropriate values
      if (result == '') {
        Logger.warning('SMS cancelled (null/empty return value)');
        return 'cancelled';
      } else if (result.toString().toLowerCase().contains('error') ||
          result.toString().toLowerCase().contains('fail') ||
          result.toString().toLowerCase().contains('cancel')) {
        Logger.warning('SMS cancelled (error in return value: $result)');
        return 'cancelled';
      } else {
        // If we get any other return value, assume it was sent
        // The native iOS delegate should handle cancellation properly
        Logger.success('SMS sent successfully (return value: $result)');
        return 'sent';
      }
    } catch (e) {
      Logger.error('SMS error: $e');
      return 'cancelled';
    }
  }

  // Share group contacts as CSV
  void _shareGroupContacts() async {
    try {
      // Create VCF content
      final vcfLines = <String>[];

      // Add contact data - each contact needs its own BEGIN:VCARD and VERSION:3.0
      for (final contact in widget.conversation.contacts) {
        // Add VCF header for each contact
        vcfLines.add('BEGIN:VCARD');
        vcfLines.add('VERSION:3.0');
        final fullName = contact.displayName ?? 'Unknown';
        final nameParts = fullName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName =
            nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

        // Add name
        vcfLines.add('FN:$fullName');
        vcfLines.add('N:$lastName;$firstName;;;');

        // Add phone numbers with proper types
        if (contact.phones != null && contact.phones!.isNotEmpty) {
          for (var phone in contact.phones!) {
            final phoneType = phone.label?.toUpperCase() ?? 'CELL';
            vcfLines.add('TEL;TYPE=$phoneType:${phone.value ?? ''}');
          }
        }

        // Add email addresses with proper types
        if (contact.emails != null && contact.emails!.isNotEmpty) {
          for (var email in contact.emails!) {
            final emailType = email.label?.toUpperCase() ?? 'HOME';
            vcfLines.add('EMAIL;TYPE=$emailType:${email.value ?? ''}');
          }
        }

        // Add VCF footer
        vcfLines.add('END:VCARD');
        vcfLines.add(''); // Empty line between contacts
      }

      final vcfString = vcfLines.join('\n');

      // Create temporary file with proper VCF extension
      final directory = await getTemporaryDirectory();
      final groupName =
          widget.conversation.name?.replaceAll(' ', '_') ?? 'Unnamed_Group';
      final fileName = '$groupName.vcf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(vcfString);

      // Share the VCF file (no text, just the file)
      await Share.shareXFiles([XFile(file.path)]);

      Logger.success('Group contacts shared successfully');
    } catch (e) {
      Logger.error('Error sharing group contacts', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing contacts: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  // Show popup when user cancels sending
  Future<bool> _showCancelConfirmationDialog() async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Would you like to'),
        content: const Text(
            'Stop sending messages or continue with the next recipient?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Stop'),
            onPressed: () => Navigator.pop(context, true), // true = stop
          ),
          CupertinoDialogAction(
            child: const Text('Continue'),
            onPressed: () => Navigator.pop(context, false), // false = continue
          ),
        ],
      ),
    );

    return result ?? false; // Default to stop if dialog is dismissed
  }

  // Helper method to send Email and detect cancellation
  Future<String> _sendEmailWithStatusDetection(
      String content, String emailAddress, Contact contact) async {
    final subject = 'Message from ${contact.displayName ?? 'Contact'}';
    final personalizedContent = _replaceTemplateVariables(content, contact);

    final Email email = Email(
      body: personalizedContent,
      subject: subject,
      recipients: [emailAddress],
      isHTML: false,
    );

    // Convert Email to MailOptions for flutter_mailer
    final MailOptions mailOptions = MailOptions(
      body: email.body,
      subject: email.subject,
      recipients: email.recipients,
      isHTML: email.isHTML,
    );

    // Use flutter_mailer which has better iOS support and return values
    final MailerResponse result = await FlutterMailer.send(mailOptions);
    Logger.info('Email send result: $result');

    // Check the result from flutter_mailer
    switch (result) {
      case MailerResponse.sent:
        Logger.success('Email sent successfully');
        return 'sent';
      case MailerResponse.saved:
        Logger.success('Email saved to drafts');
        return 'sent';
      case MailerResponse.cancelled:
        Logger.warning('Email cancelled by user');
        return 'cancelled';
      default:
        Logger.warning('Email result unknown: $result');
        return 'cancelled';
    }
  }
}
