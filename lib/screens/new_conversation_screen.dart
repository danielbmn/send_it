import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/conversation.dart';
import '../models/contact_info.dart';
import '../models/contact_group.dart';
import '../models/message_template.dart';
import '../utils/helpers.dart';
import '../widgets/expandable_contact_tile.dart';
import '../services/storage_service.dart';
import 'conversation_screen.dart';

class NewConversationScreen extends StatefulWidget {
  final Function(Conversation) onConversationCreated;
  final List<Conversation> existingConversations;
  final List<MessageTemplate> templates;

  NewConversationScreen({
    required this.onConversationCreated,
    required this.existingConversations,
    required this.templates,
  });

  @override
  _NewConversationScreenState createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends State<NewConversationScreen>
    with WidgetsBindingObserver {
  List<Contact> _allContacts = [];
  Set<ContactInfo> _selectedContactInfos = {};
  bool _loading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh contacts when app becomes active again
    if (state == AppLifecycleState.resumed) {
      _refreshContactsPreservingSelections();
    }
  }

  List<Contact> get _filteredContacts {
    if (_searchQuery.isEmpty) {
      return _allContacts;
    }
    return _allContacts.where((contact) {
      final name = contact.displayName?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      // Search in name
      if (name.contains(query)) return true;

      // Search in phone numbers
      if (contact.phones != null) {
        for (var phone in contact.phones!) {
          if (phone.value?.contains(query) == true) return true;
        }
      }

      // Search in emails
      if (contact.emails != null) {
        for (var email in contact.emails!) {
          if (email.value?.toLowerCase().contains(query) == true) return true;
        }
      }

      return false;
    }).toList();
  }

  void _handleContactInfoToggle(ContactInfo info, bool selected) {
    setState(() {
      if (selected) {
        _selectedContactInfos.add(info);
      } else {
        _selectedContactInfos.remove(info);
      }
    });
  }

  // Convert selected ContactInfos to Contacts for creating conversation
  List<Contact> _getSelectedContacts() {
    // Group by contact and create Contact entries with selected phones/emails
    final Map<String, Contact> contactMap = {};

    for (var info in _selectedContactInfos) {
      final key = info.contact.displayName ?? 'Unknown';
      if (!contactMap.containsKey(key)) {
        // Create a new contact with only the selected info
        contactMap[key] = Contact(
          displayName: info.contact.displayName,
          phones: info.type == ContactInfoType.phone
              ? [Item(value: info.value, label: info.label)]
              : [],
          emails: info.type == ContactInfoType.email
              ? [Item(value: info.value, label: info.label)]
              : [],
        );
      } else {
        // Add to existing contact
        if (info.type == ContactInfoType.phone) {
          contactMap[key]!.phones ??= [];
          contactMap[key]!
              .phones!
              .add(Item(value: info.value, label: info.label));
        } else {
          contactMap[key]!.emails ??= [];
          contactMap[key]!
              .emails!
              .add(Item(value: info.value, label: info.label));
        }
      }
    }

    return contactMap.values.toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadContacts();
  }

  Future<void> _refreshContactsPreservingSelections() async {
    try {
      print('🔄 Refreshing contacts on app resume...');

      // Check contacts permission first
      final permissionStatus = await Permission.contacts.status;
      print('🔐 Contacts permission status: $permissionStatus');

      if (permissionStatus.isDenied || permissionStatus.isPermanentlyDenied) {
        print('⚠️ Contacts permission denied, skipping refresh');
        return; // Skip refresh if permission is denied
      }

      // Store currently selected phone numbers and emails to preserve selections
      final selectedPhoneNumbers = _selectedContactInfos
          .where((info) => info.type == ContactInfoType.phone)
          .map((info) => StorageService.normalizePhone(info.value))
          .toSet();
      final selectedEmails = _selectedContactInfos
          .where((info) => info.type == ContactInfoType.email)
          .map((info) => info.value.toLowerCase())
          .toSet();

      print(
          '📋 Preserving ${selectedPhoneNumbers.length} phone + ${selectedEmails.length} email selections');

      // Load fresh contacts from device
      final contacts = await ContactsService.getContacts(withThumbnails: false);
      final contactsList = contacts.where((contact) {
        return contact.displayName != null && contact.displayName!.isNotEmpty;
      }).toList();

      // Rebuild selected ContactInfos based on fresh contact data
      final newSelectedInfos = <ContactInfo>{};

      for (var contact in contactsList) {
        // Check phones
        if (contact.phones != null) {
          for (var phone in contact.phones!) {
            if (phone.value != null && phone.value!.isNotEmpty) {
              final normalizedPhone =
                  StorageService.normalizePhone(phone.value);
              if (selectedPhoneNumbers.contains(normalizedPhone)) {
                final label = phone.label?.toLowerCase() ?? '';
                if (!label.contains('fax')) {
                  newSelectedInfos.add(ContactInfo(
                    contact: contact,
                    value: phone.value!,
                    type: ContactInfoType.phone,
                    label: phone.label,
                  ));
                  print(
                      '  ✅ Restored phone selection: ${contact.displayName} - $normalizedPhone');
                }
              }
            }
          }
        }

        // Check emails
        if (contact.emails != null) {
          for (var email in contact.emails!) {
            if (email.value != null && email.value!.isNotEmpty) {
              if (selectedEmails.contains(email.value!.toLowerCase())) {
                newSelectedInfos.add(ContactInfo(
                  contact: contact,
                  value: email.value!,
                  type: ContactInfoType.email,
                  label: email.label,
                ));
                print(
                    '  ✅ Restored email selection: ${contact.displayName} - ${email.value}');
              }
            }
          }
        }
      }

      setState(() {
        _allContacts = contactsList;
        _selectedContactInfos = newSelectedInfos;
      });

      print(
          '✅ Contacts refreshed: ${contactsList.length} total, ${newSelectedInfos.length} selected');
    } catch (e) {
      print('❌ Error refreshing contacts: $e');
    }
  }

  Future<void> _loadContacts() async {
    try {
      print('🔍 Loading contacts for new conversation...');

      // Try to access contacts directly to test if permission is actually working
      try {
        await ContactsService.getContacts(withThumbnails: false);
        print('✅ Contacts access successful, permission is working');
      } catch (e) {
        print('❌ Contacts access failed: $e');

        // Check permission status and request if needed
        final permissionStatus = await Permission.contacts.status;
        print('🔐 Contacts permission status: $permissionStatus');

        if (permissionStatus.isDenied) {
          print('🔐 Requesting contacts permission...');
          final result = await Permission.contacts.request();
          print('🔐 Permission request result: $result');

          if (result.isDenied || result.isPermanentlyDenied) {
            setState(() {
              _errorMessage =
                  'Contacts permission is required to create messages';
              _loading = false;
            });
            return;
          }
        } else {
          setState(() {
            _errorMessage =
                'Unable to access contacts. Please check app permissions in Settings.';
            _loading = false;
          });
          return;
        }
      }

      // Get fresh contacts data
      final contacts = await ContactsService.getContacts(withThumbnails: false);
      print('📱 Raw contacts loaded: ${contacts.length}');

      // Debug: Print all contact names
      for (final contact in contacts) {
        print(
            '📱 Contact: ${contact.displayName} - ${contact.phones?.length ?? 0} phones');
      }

      final contactsList = contacts.where((contact) {
        return contact.displayName != null && contact.displayName!.isNotEmpty;
      }).toList();

      setState(() {
        _allContacts = contactsList;
        _loading = false;
        print('📱 Loaded ${_allContacts.length} contacts');
        if (_allContacts.isEmpty) {
          _errorMessage = 'No contacts found';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Error loading contacts: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Message'),
        backgroundColor: Color(0xFFF9F9F9),
        elevation: 0,
        leading: CupertinoButton(
          child: Icon(CupertinoIcons.xmark, color: Color(0xFF007AFF)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_selectedContactInfos.isNotEmpty)
            CupertinoButton(
              child: Text('Next',
                  style: TextStyle(
                      color: Color(0xFF007AFF), fontWeight: FontWeight.bold)),
              onPressed: _createConversation,
            ),
        ],
      ),
      body: _loading
          ? Center(child: CupertinoActivityIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.exclamationmark_circle,
                          size: 64, color: Color(0xFFFF3B30)),
                      SizedBox(height: 16),
                      Text(_errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8E8E93))),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_selectedContactInfos.isNotEmpty)
                      Container(
                        height: 60,
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedContactInfos.length,
                          itemBuilder: (context, index) {
                            final info = _selectedContactInfos.elementAt(index);
                            return Container(
                              margin: EdgeInsets.only(right: 8),
                              child: Chip(
                                avatar: Icon(
                                  info.type == ContactInfoType.phone
                                      ? CupertinoIcons.phone_fill
                                      : CupertinoIcons.mail_solid,
                                  size: 16,
                                  color: Color(0xFF007AFF),
                                ),
                                label: Text(
                                    '${info.contact.displayName}: ${info.displayValue}',
                                    style: TextStyle(fontSize: 12)),
                                deleteIcon: Icon(
                                    CupertinoIcons.xmark_circle_fill,
                                    size: 16),
                                onDeleted: () {
                                  setState(() {
                                    _selectedContactInfos.remove(info);
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    // Search bar
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: CupertinoSearchTextField(
                        controller: _searchController,
                        placeholder: 'Search contacts',
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        onSuffixTap: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: _filteredContacts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.search,
                                      size: 48, color: Color(0xFF8E8E93)),
                                  SizedBox(height: 16),
                                  Text('No contacts found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Color(0xFF8E8E93),
                                      )),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.only(bottom: 100),
                              itemCount: _filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = _filteredContacts[index];
                                return ExpandableContactTile(
                                  contact: contact,
                                  selectedContactInfos: _selectedContactInfos,
                                  onContactInfoToggle: _handleContactInfoToggle,
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  void _createConversation() {
    // Check if a conversation with the same contact methods already exists
    final existingConversation = _findMatchingConversation();

    if (existingConversation != null) {
      // Navigate to existing conversation
      _navigateToConversation(existingConversation);
      return;
    }

    // Allow creating conversations with 0 contacts - user can add members later
    final selectedContacts = _getSelectedContacts();
    // Show naming dialog for groups with multiple contacts or empty groups
    if (selectedContacts.length > 1 || selectedContacts.isEmpty) {
      _showGroupNamingDialog();
    } else {
      _createConversationWithName(null);
    }
  }

  // Check if a conversation with the exact same contact methods exists
  // Returns the newest matching conversation if multiple exist
  Conversation? _findMatchingConversation() {
    // Get all selected contact method identifiers (name + value)
    final selectedMethods = _selectedContactInfos.map((info) {
      return '${info.contact.displayName}_${info.value}';
    }).toSet();

    List<Conversation> matchingConversations = [];

    // Check each existing conversation
    for (var conversation in widget.existingConversations) {
      // Get all contact methods from this conversation
      final allMethods = Helpers.extractContactMethods(conversation.contacts);
      final conversationMethods = allMethods.map((method) {
        return '${method.contact.displayName}_${method.value}';
      }).toSet();

      // Check if the sets match exactly
      if (selectedMethods.length == conversationMethods.length &&
          selectedMethods.difference(conversationMethods).isEmpty) {
        matchingConversations.add(conversation);
      }
    }

    // If multiple matches found, return the newest one (by lastMessageTime)
    if (matchingConversations.isNotEmpty) {
      matchingConversations.sort((a, b) =>
          b.lastMessageTime.compareTo(a.lastMessageTime)); // Newest first
      final newest = matchingConversations.first;
      print(
          '✅ Found ${matchingConversations.length} matching conversation(s), using newest: ${newest.name ?? "Unnamed"}');
      return newest;
    }

    return null;
  }

  void _navigateToConversation(Conversation conversation) {
    // Close this screen and open the conversation
    Navigator.pop(context); // Close new conversation screen
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => ConversationScreen(
          conversation: conversation,
          templates: widget.templates,
          onMessageSent: (message) {
            // Update conversation with new message
            conversation.messages.add(message);
            conversation.lastMessageTime = message.timestamp;
            conversation.lastMessagePreview = message.content;
          },
        ),
      ),
    );
  }

  void _showGroupNamingDialog() {
    final nameController = TextEditingController();

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Name Group'),
        content: Column(
          children: [
            Text('Give this group a name (optional)'),
            SizedBox(height: 16),
            CupertinoTextField(
              controller: nameController,
              placeholder: 'Group name',
              autofocus: true,
              maxLength: 50,
              decoration: BoxDecoration(
                border: Border.all(color: Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: Text('Skip'),
            onPressed: () {
              Navigator.pop(context);
              _createConversationWithName(null);
            },
          ),
          CupertinoDialogAction(
            child: Text('Create'),
            onPressed: () {
              Navigator.pop(context);
              _createConversationWithName(nameController.text.trim().isEmpty
                  ? null
                  : nameController.text.trim());
            },
          ),
        ],
      ),
    );
  }

  void _createConversationWithName(String? name) {
    final selectedContacts = _getSelectedContacts();
    final conversation = Conversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      contacts: selectedContacts,
      messages: [],
      lastMessageTime: DateTime.now(),
      lastMessagePreview: 'No messages yet',
    );

    // Save as a group for persistence
    _saveConversationAsGroup(conversation);

    // Notify parent that conversation was created
    widget.onConversationCreated(conversation);

    // Navigate to the new conversation
    _navigateToConversation(conversation);
  }

  Future<void> _saveConversationAsGroup(Conversation conversation) async {
    try {
      final groups = await StorageService.loadGroups();
      final group = ContactGroup(
        id: conversation.id,
        name: conversation.name ?? '',
        contacts: conversation.contacts,
      );
      groups.add(group);
      await StorageService.saveGroups(groups);
      print('💾 Saved new conversation as group');
    } catch (e) {
      print('❌ Error saving conversation: $e');
    }
  }
}
