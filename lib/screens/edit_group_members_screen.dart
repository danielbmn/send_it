import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/conversation.dart';
import '../models/contact_info.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import '../widgets/expandable_contact_tile.dart';

class EditGroupMembersScreen extends StatefulWidget {
  final Conversation conversation;
  final Function(List<Contact>) onMembersUpdated;

  const EditGroupMembersScreen({
    super.key,
    required this.conversation,
    required this.onMembersUpdated,
  });

  @override
  _EditGroupMembersScreenState createState() => _EditGroupMembersScreenState();
}

class _EditGroupMembersScreenState extends State<EditGroupMembersScreen>
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

  Future<void> _refreshContactsPreservingSelections() async {
    try {
      Logger.info('Refreshing contacts on app resume...');

      // Check contacts permission first
      final permissionStatus = await Permission.contacts.status;
      Logger.info('Contacts permission status: $permissionStatus');

      if (permissionStatus.isDenied || permissionStatus.isPermanentlyDenied) {
        Logger.warning('Contacts permission denied, skipping refresh');
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

      Logger.info(
          'Preserving ${selectedPhoneNumbers.length} phone + ${selectedEmails.length} email selections');

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
                  Logger.success(
                      'Restored phone selection: ${contact.displayName} - $normalizedPhone');
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
                Logger.success(
                    'Restored email selection: ${contact.displayName} - ${email.value}');
              }
            }
          }
        }
      }

      setState(() {
        _allContacts = contactsList;
        _selectedContactInfos = newSelectedInfos;
      });

      Logger.success(
          'Contacts refreshed: ${contactsList.length} total, ${newSelectedInfos.length} selected');
    } catch (e) {
      Logger.error('Error refreshing contacts', e);
    }
  }

  List<Contact> get _filteredContacts {
    if (_searchQuery.isEmpty) {
      return _allContacts;
    }
    return _allContacts.where((contact) {
      final name = contact.displayName?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      if (name.contains(query)) return true;

      if (contact.phones != null) {
        for (var phone in contact.phones!) {
          if (phone.value?.contains(query) == true) return true;
        }
      }

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

  // Convert selected ContactInfos to Contacts for saving
  List<Contact> _getSelectedContacts() {
    final Map<String, Contact> contactMap = {};

    for (var info in _selectedContactInfos) {
      final key = info.contact.displayName ?? 'Unknown';
      if (!contactMap.containsKey(key)) {
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

  // Convert existing conversation contacts to ContactInfos for initial selection
  void _initializeSelectedContactInfos() {
    for (var contact in widget.conversation.contacts) {
      if (contact.phones != null) {
        for (var phone in contact.phones!) {
          if (phone.value != null && phone.value!.isNotEmpty) {
            _selectedContactInfos.add(ContactInfo(
              contact: contact,
              value: phone.value!,
              type: ContactInfoType.phone,
              label: phone.label,
            ));
          }
        }
      }
      if (contact.emails != null) {
        for (var email in contact.emails!) {
          if (email.value != null && email.value!.isNotEmpty) {
            _selectedContactInfos.add(ContactInfo(
              contact: contact,
              value: email.value!,
              type: ContactInfoType.email,
              label: email.label,
            ));
          }
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSelectedContactInfos();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      Logger.info('Loading contacts for group editing...');
      // Get fresh contacts data
      final contacts = await ContactsService.getContacts(withThumbnails: false);
      Logger.info('Raw contacts loaded: ${contacts.length}');

      // Debug: Print all contact names
      for (final contact in contacts) {
        Logger.info(
            'Contact: ${contact.displayName} - ${contact.phones?.length ?? 0} phones');
      }

      final contactsList = contacts.where((contact) {
        return contact.displayName != null && contact.displayName!.isNotEmpty;
      }).toList();

      setState(() {
        _allContacts = contactsList;
        _loading = false;
        Logger.info('Loaded ${_allContacts.length} contacts');
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
        title: const Text('Edit Group Members'),
        backgroundColor: const Color(0xFFF9F9F9),
        elevation: 0,
        leading: CupertinoButton(
          child: const Icon(CupertinoIcons.xmark, color: Color(0xFF007AFF)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
            onPressed: _saveChanges,
            child: const Text('Save',
                style: TextStyle(
                    color: Color(0xFF007AFF), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_circle,
                          size: 64, color: Color(0xFFFF3B30)),
                      const SizedBox(height: 16),
                      Text(_errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF8E8E93))),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_selectedContactInfos.isNotEmpty)
                      Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedContactInfos.length,
                          itemBuilder: (context, index) {
                            final info = _selectedContactInfos.elementAt(index);
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Chip(
                                avatar: Icon(
                                  info.type == ContactInfoType.phone
                                      ? CupertinoIcons.phone_fill
                                      : CupertinoIcons.mail_solid,
                                  size: 16,
                                  color: const Color(0xFF007AFF),
                                ),
                                label: Text(
                                    '${info.contact.displayName}: ${info.displayValue}',
                                    style: const TextStyle(fontSize: 12)),
                                deleteIcon: const Icon(
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                          ? const Center(
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
                              padding: const EdgeInsets.only(bottom: 100),
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

  void _saveChanges() {
    // Allow groups to have 0 recipients - user can add members later
    final selectedContacts = _getSelectedContacts();
    widget.onMembersUpdated(selectedContacts);
    Navigator.pop(context);
  }
}
