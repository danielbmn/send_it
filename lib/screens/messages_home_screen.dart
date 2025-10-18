import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../models/conversation.dart';
import '../models/message_template.dart';
import '../models/contact_group.dart';
import '../services/storage_service.dart';
import 'new_conversation_screen.dart';
import 'conversation_screen.dart';
import 'create_template_screen.dart';
import '../utils/logger.dart';

class MessagesHomeScreen extends StatefulWidget {
  const MessagesHomeScreen({super.key});

  @override
  _MessagesHomeScreenState createState() => _MessagesHomeScreenState();
}

class _MessagesHomeScreenState extends State<MessagesHomeScreen>
    with WidgetsBindingObserver {
  List<Conversation> _conversations = [];
  List<MessageTemplate> _templates = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _messagesScrollController.addListener(_handleScroll);
    Logger.info('Messages app started - loading conversations');
  }

  void _handleScroll() {
    // Show search bar when scrolled to top and trying to scroll more (overscroll)
    if (_messagesScrollController.hasClients) {
      final offset = _messagesScrollController.offset;
      if (offset < -50 && !_showSearchBar) {
        setState(() {
          _showSearchBar = true;
        });
      }
    }
  }

  List<Conversation> get _filteredConversations {
    if (_searchQuery.isEmpty) {
      return _conversations;
    }
    return _conversations.where((conversation) {
      final name = conversation.name?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      // Search in conversation name
      if (name.contains(query)) return true;

      // Search in contact names
      for (var contact in conversation.contacts) {
        if (contact.displayName?.toLowerCase().contains(query) == true) {
          return true;
        }
      }

      // Search in message content
      for (var message in conversation.messages) {
        if (message.content.toLowerCase().contains(query)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messagesScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Logger.info('App resumed - validating conversations');
      _validateConversationsOnResume();
      _checkContactPermissionsOnResume();
    }
  }

  Future<void> _checkContactPermissionsOnResume() async {
    try {
      // First, try to actually access contacts to see if we can
      try {
        final contacts = await ContactsService.getContacts();
        if (contacts.isNotEmpty) {
          Logger.info(
              'Contacts accessible - ${contacts.length} contacts found');
          return; // We have access, no need to show dialog
        }
      } catch (e) {
        Logger.warning('Cannot access contacts: $e');
      }

      // If we can't access contacts, check permission status
      final permission = await Permission.contacts.status;
      Logger.info('Contact permission status: $permission');

      // Only show dialog if permission was explicitly denied
      if (permission == PermissionStatus.denied) {
        Logger.info(
            'Contact permissions explicitly denied - requesting permission');

        // Show dialog to request permission
        if (mounted) {
          showCupertinoDialog(
            context: context,
            builder: (context) => CupertinoAlertDialog(
              title: const Text('Contact Access Required'),
              content: const Text(
                'This app needs access to your contacts to send messages. Please grant permission in Settings.',
              ),
              actions: [
                CupertinoDialogAction(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoDialogAction(
                  child: const Text('Settings'),
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                ),
              ],
            ),
          );
        }
      } else {
        // Permission is undetermined, granted, or restricted - don't show dialog
        Logger.info(
            'Contact permission status: $permission - not showing dialog');
      }
    } catch (e) {
      Logger.error('Error checking contact permissions', e);
    }
  }

  Future<void> _loadData() async {
    try {
      Logger.info('Loading initial data...');

      // Start with empty data to ensure app loads
      setState(() {
        _conversations = [];
        _templates = [];
        _isLoading = false;
      });

      Logger.success('App loaded with empty state');

      // Try to load real data in background
      try {
        Logger.info('Loading groups...');
        final groups = await StorageService.loadGroups();
        Logger.success('Loaded ${groups.length} groups');

        Logger.info('Loading templates...');
        final templates = await StorageService.loadTemplates();
        Logger.success('Loaded ${templates.length} templates');

        Logger.info('Converting groups to conversations...');
        // Convert groups to conversations
        final conversations = await _convertGroupsToConversations(groups);
        Logger.success('Converted ${conversations.length} conversations');

        // Sort by lastMessageTime - newest first
        conversations
            .sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

        setState(() {
          _conversations = conversations;
          _templates = templates;
        });

        Logger.success('Conversations loaded successfully');
      } catch (e) {
        Logger.warning('Error loading real data, keeping empty state: $e');
        Logger.warning('Stack trace: ${StackTrace.current}');
      }
    } catch (e) {
      Logger.error('Critical error in _loadData', e);

      // Always set loading to false to prevent infinite loading
      setState(() {
        _conversations = [];
        _templates = [];
        _isLoading = false;
      });
    }
  }

  Future<List<Conversation>> _convertGroupsToConversations(
      List<ContactGroup> groups) async {
    final conversations = <Conversation>[];

    try {
      Logger.info('Loading messages...');
      final allMessages = await StorageService.loadMessages();
      Logger.success('Loaded ${allMessages.length} messages');

      for (final group in groups) {
        try {
          // Get messages for this conversation
          final conversationMessages = allMessages
              .where((message) => message.groupId == group.id)
              .toList();

          // Sort messages by timestamp - oldest first (normal messaging behavior)
          conversationMessages.sort((a, b) => a.timestamp
              .compareTo(b.timestamp)); // Oldest first, newest at bottom

          // Get last message info
          DateTime lastMessageTime =
              DateTime.now().subtract(const Duration(days: 1));
          String? lastMessagePreview = 'No messages yet';

          if (conversationMessages.isNotEmpty) {
            final lastMessage = conversationMessages.last;
            lastMessageTime = lastMessage.timestamp;
            lastMessagePreview = lastMessage.content;
          }

          // Create conversation from group
          final conversation = Conversation(
            id: group.id,
            name: group.name,
            contacts: group.contacts,
            messages: conversationMessages,
            lastMessageTime: lastMessageTime,
            lastMessagePreview: lastMessagePreview,
          );
          conversations.add(conversation);
        } catch (e) {
          Logger.warning('Error processing group ${group.name}: $e');
          // Continue with other groups even if one fails
        }
      }

      return conversations;
    } catch (e) {
      Logger.error('Error converting groups to conversations', e);
      return []; // Return empty list instead of crashing
    }
  }

  Future<void> _validateConversationsOnResume() async {
    try {
      Logger.info('Validating conversations on app resume...');
      final groups = await StorageService.loadGroups();

      // Only validate groups if we have permission and groups exist
      List<ContactGroup> validatedGroups = groups;
      try {
        validatedGroups = await StorageService.validateAndCleanGroups(groups);
      } catch (e) {
        Logger.warning('Group validation failed, using existing groups: $e');
        validatedGroups = groups; // Use existing groups if validation fails
      }

      final conversations =
          await _convertGroupsToConversations(validatedGroups);

      // Sort by lastMessageTime - newest first
      conversations
          .sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

      setState(() {
        _conversations = conversations;
      });
      Logger.info('Conversations updated after app resume');
    } catch (e) {
      Logger.error('Error validating conversations on resume', e);
      // Don't crash the app, just log the error
    }
  }

  Future<void> _refreshConversations() async {
    try {
      Logger.info('Refreshing conversations...');

      final groups = await StorageService.loadGroups();

      // Only validate groups if we have permission and groups exist
      List<ContactGroup> validatedGroups = groups;
      try {
        validatedGroups = await StorageService.validateAndCleanGroups(groups);
      } catch (e) {
        Logger.warning('Group validation failed, using existing groups: $e');
        validatedGroups = groups; // Use existing groups if validation fails
      }

      final conversations =
          await _convertGroupsToConversations(validatedGroups);

      // Sort by lastMessageTime - newest first
      conversations
          .sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));

      setState(() {
        _conversations = conversations;
      });
      Logger.info('Conversations refreshed');
    } catch (e) {
      Logger.error('Error refreshing conversations', e);
      // Don't crash the app, just log the error
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(radius: 20),
              SizedBox(height: 16),
              Text('Loading conversations...',
                  style: TextStyle(color: Color(0xFF8E8E93))),
            ],
          ),
        ),
      );
    }

    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: const Color(0xFFF9F9F9),
        activeColor: const Color(0xFF007AFF),
        inactiveColor: const Color(0xFF8E8E93),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.doc_text),
            label: 'Templates',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        if (index == 0) {
          return _buildMessagesTab();
        } else {
          return _buildTemplatesTab();
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.chat_bubble_2,
              size: 64, color: Color(0xFF8E8E93)),
          SizedBox(height: 16),
          Text('No Conversations',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8E8E93),
              )),
          SizedBox(height: 8),
          Text('Start a new conversation by tapping the + button',
              style: TextStyle(color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }

  Widget _buildMessagesTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF9F9F9),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.square_arrow_down),
            onPressed: _importContacts,
            tooltip: 'Import Contacts',
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.square_pencil),
            onPressed: _startNewConversation,
          ),
        ],
      ),
      body: _conversations.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                // Search bar that shows/hides
                if (_showSearchBar)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFFF9F9F9),
                    child: CupertinoSearchTextField(
                      controller: _searchController,
                      placeholder: 'Search messages',
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      onSuffixTap: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                          _showSearchBar = false;
                        });
                      },
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshConversations,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is OverscrollNotification) {
                          if (notification.overscroll < -50 &&
                              !_showSearchBar) {
                            setState(() {
                              _showSearchBar = true;
                            });
                          }
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _messagesScrollController,
                        padding: const EdgeInsets.only(bottom: 50),
                        itemCount: _filteredConversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _filteredConversations[index];
                          return Column(
                            children: [
                              Dismissible(
                                key: Key(conversation.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: const Color(0xFFFF3B30),
                                  child: const Icon(
                                    CupertinoIcons.delete,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                confirmDismiss: (direction) async {
                                  return await showCupertinoDialog(
                                    context: context,
                                    builder: (context) => CupertinoAlertDialog(
                                      title: const Text('Delete Conversation'),
                                      content: const Text(
                                          'Are you sure you want to delete this conversation? This action cannot be undone.'),
                                      actions: [
                                        CupertinoDialogAction(
                                          child: const Text('Cancel'),
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                        ),
                                        CupertinoDialogAction(
                                          child: const Text('Delete',
                                              style: TextStyle(
                                                  color: Color(0xFFFF3B30))),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDismissed: (direction) async {
                                  await _deleteConversation(conversation);
                                },
                                child: _buildConversationTile(conversation),
                              ),
                              if (index < _filteredConversations.length - 1)
                                Container(
                                  height: 1,
                                  color: const Color(0xFFE5E5EA),
                                  margin: const EdgeInsets.only(
                                      left: 80, right: 16),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTemplatesTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF9F9F9),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: _createNewTemplate,
          ),
        ],
      ),
      body: _templates.isEmpty
          ? _buildEmptyTemplatesState()
          : ListView.builder(
              padding: const EdgeInsets.only(
                  bottom:
                      50), // Reduced padding to show partial content at bottom
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                return Column(
                  children: [
                    _buildTemplateTile(template),
                    if (index < _templates.length - 1)
                      Container(
                        height: 1,
                        color: const Color(0xFFE5E5EA),
                        margin: const EdgeInsets.only(left: 16, right: 16),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEmptyTemplatesState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.doc_text, size: 64, color: Color(0xFF8E8E93)),
          SizedBox(height: 16),
          Text('No Templates',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF8E8E93),
              )),
          SizedBox(height: 8),
          Text('Create message templates to use in conversations',
              style: TextStyle(color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }

  Widget _buildTemplateTile(MessageTemplate template) {
    return ListTile(
      title: Text(template.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        template.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF8E8E93)),
      ),
      trailing: IconButton(
        icon: const Icon(CupertinoIcons.pencil, color: Color(0xFF007AFF)),
        onPressed: () => _editTemplate(template),
      ),
      onTap: () => _editTemplate(template),
    );
  }

  Widget _buildConversationTile(Conversation conversation) {
    final hasTitle = conversation.name != null && conversation.name!.isNotEmpty;

    return ListTile(
      leading: _buildConversationAvatar(conversation),
      title: hasTitle
          ? Text(
              conversation.name!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : ShaderMask(
              shaderCallback: (bounds) {
                return const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0.0, 0.8, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: Text(
                _getContactNames(conversation.contacts),
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
      subtitle: Text(
        conversation.lastMessagePreview ?? 'No messages yet',
        style: const TextStyle(color: Color(0xFF8E8E93)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatTime(conversation.lastMessageTime),
        style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
      ),
      onTap: () => _openConversation(conversation),
    );
  }

  // Color palette for avatars - pastel colors
  static const List<Color> _avatarColors = [
    Color(0xFF87CEEB), // Sky Blue
    Color(0xFFB19CD9), // Lavender
    Color(0xFFFFB6C1), // Light Pink
    Color(0xFFFFB347), // Pastel Orange
    Color(0xFFFFD966), // Darker Pastel Yellow
    Color(0xFF98D8C8), // Mint Green
    Color(0xFF89CFF0), // Baby Blue
    Color(0xFFFF9999), // Pastel Red
  ];

  Color _getAvatarColor(String conversationId) {
    // Use conversation ID to consistently pick a color
    final hash = conversationId.hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  Widget _buildConversationAvatar(Conversation conversation) {
    final avatarColor = _getAvatarColor(conversation.id);

    if (conversation.contacts.isEmpty) {
      // Empty group
      return const CircleAvatar(
        backgroundColor: Color(0xFF8E8E93),
        child: Icon(
          CupertinoIcons.person_add,
          color: Colors.white,
          size: 20,
        ),
      );
    } else if (conversation.contacts.length == 1) {
      // Single contact
      final contact = conversation.contacts.first;
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
          '${conversation.contacts.length}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: conversation.contacts.length > 99 ? 12 : 16,
          ),
        ),
      );
    }
  }

  String _getContactNames(List<Contact> contacts) {
    if (contacts.isEmpty) return 'Unknown';
    // List all FIRST names only, separated by commas (will be faded at end by ShaderMask)
    return contacts.map((c) {
      final fullName = c.displayName ?? 'Unknown';
      // Extract first name (first word before space)
      return fullName.split(' ').first;
    }).join(', ');
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  void _startNewConversation() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => NewConversationScreen(
          existingConversations: _conversations,
          templates: _templates,
          onConversationCreated: (conversation) {
            setState(() {
              _conversations.insert(0, conversation);
            });
          },
        ),
      ),
    ).then((_) {
      // Refresh conversations when returning
      _loadData();
    });
  }

  void _openConversation(Conversation conversation) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => ConversationScreen(
          conversation: conversation,
          templates: _templates,
          onMessageSent: (message) {
            // Update conversation with new message
            setState(() {
              conversation.messages.add(message);
              conversation.lastMessageTime = message.timestamp;
              conversation.lastMessagePreview = message.content;
            });
          },
        ),
      ),
    ).then((_) {
      // Refresh conversations when returning from conversation screen
      _loadData();
    });
  }

  void _createNewTemplate() async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => const CreateTemplateScreen(),
      ),
    );

    if (result != null) {
      // Save the new template to storage
      final templates = await StorageService.loadTemplates();
      templates.add(result);
      await StorageService.saveTemplates(templates);

      // Refresh templates when returning
      _loadData();
    }
  }

  void _editTemplate(MessageTemplate template) async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => CreateTemplateScreen(template: template),
      ),
    );

    if (result == 'DELETE') {
      // Delete the template from storage
      final templates = await StorageService.loadTemplates();
      templates.removeWhere((t) => t.id == template.id);
      await StorageService.saveTemplates(templates);

      // Refresh templates when returning
      _loadData();
    } else if (result != null) {
      // Update the template in storage
      final templates = await StorageService.loadTemplates();
      final index = templates.indexWhere((t) => t.id == template.id);
      if (index != -1) {
        templates[index] = result;
        await StorageService.saveTemplates(templates);
      }

      // Refresh templates when returning
      _loadData();
    }
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    try {
      // Remove from conversations list
      setState(() {
        _conversations.removeWhere((c) => c.id == conversation.id);
      });

      // Remove group from storage
      final groups = await StorageService.loadGroups();
      groups.removeWhere((g) => g.id == conversation.id);
      await StorageService.saveGroups(groups);

      // Remove messages from storage
      final messages = await StorageService.loadMessages();
      messages.removeWhere((m) => m.groupId == conversation.id);
      await StorageService.saveMessages(messages);

      Logger.info('Deleted conversation: ${conversation.name ?? 'Unnamed'}');
    } catch (e) {
      Logger.error('Error deleting conversation', e);
    }
  }

  Future<void> _importContacts() async {
    try {
      // Pick VCF file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['vcf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          await _processVcfFile(file.path!);
        }
      }
    } catch (e) {
      Logger.error('Error importing contacts', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error importing contacts: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }

  Future<void> _processVcfFile(String filePath) async {
    try {
      final file = File(filePath);
      final vcfContent = await file.readAsString();

      // Extract contacts from VCF using manual parsing
      final contacts = <Contact>[];

      // Split by BEGIN:VCARD to get individual contacts
      final vcardBlocks = vcfContent.split('BEGIN:VCARD');

      for (final block in vcardBlocks) {
        if (block.trim().isEmpty) continue;

        final lines = block.split('\n');
        String? displayName;
        String? givenName;
        String? familyName;
        final phones = <Item>[];
        final emails = <Item>[];

        for (final line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.startsWith('FN:')) {
            displayName = trimmedLine.substring(3);
          } else if (trimmedLine.startsWith('N:')) {
            final nameParts = trimmedLine.substring(2).split(';');
            if (nameParts.length >= 2) {
              familyName = nameParts[0].isEmpty ? null : nameParts[0];
              givenName = nameParts[1].isEmpty ? null : nameParts[1];
            }
          } else if (trimmedLine.startsWith('TEL:')) {
            final phone = trimmedLine.substring(4);
            if (phone.isNotEmpty) {
              phones.add(Item(label: 'mobile', value: phone));
            }
          } else if (trimmedLine.startsWith('EMAIL:')) {
            final email = trimmedLine.substring(6);
            if (email.isNotEmpty) {
              emails.add(Item(label: 'home', value: email));
            }
          }
        }

        // Create Contact object
        if (displayName != null || givenName != null || familyName != null) {
          final contact = Contact(
            displayName:
                displayName ?? '${givenName ?? ''} ${familyName ?? ''}'.trim(),
            givenName: givenName ?? '',
            familyName: familyName ?? '',
            phones: phones,
            emails: emails,
          );

          contacts.add(contact);
        }
      }

      if (contacts.isNotEmpty) {
        // Create a new group with imported contacts
        final groupId = DateTime.now().millisecondsSinceEpoch.toString();
        final group = ContactGroup(
          id: groupId,
          name: 'Imported Contacts',
          contacts: contacts,
        );

        // Save the group
        final groups = await StorageService.loadGroups();
        groups.add(group);
        await StorageService.saveGroups(groups);

        // Refresh the UI
        _loadData();

        Logger.success('Imported ${contacts.length} contacts successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Imported ${contacts.length} contacts successfully'),
              backgroundColor: const Color(0xFF34C759),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
            ),
          );
        }
      } else {
        Logger.warning('No contacts found in VCF file');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No contacts found in the selected file'),
              backgroundColor: Color(0xFFFF9500),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(top: 100, left: 16, right: 16),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('Error processing VCF file', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing VCF file: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(top: 100, left: 16, right: 16),
          ),
        );
      }
    }
  }
}
