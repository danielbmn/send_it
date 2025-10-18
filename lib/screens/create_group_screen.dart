import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contact_group.dart';
import '../utils/logger.dart';

class CreateGroupScreen extends StatefulWidget {
  final ContactGroup? group;

  const CreateGroupScreen({super.key, this.group});

  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen>
    with WidgetsBindingObserver {
  final _nameController = TextEditingController();
  List<Contact> _selectedContacts = [];
  List<Contact> _allContacts = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.group != null) {
      _nameController.text = widget.group!.name;
      // Start with empty selection - will be populated after contacts load
      _selectedContacts = [];
    }
    _loadContacts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
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
      Logger.info('🔄 Refreshing contacts on app resume...');

      // Check contacts permission first
      final permissionStatus = await Permission.contacts.status;
      Logger.info('🔐 Contacts permission status: $permissionStatus');

      if (permissionStatus.isDenied || permissionStatus.isPermanentlyDenied) {
        Logger.info('⚠️ Contacts permission denied, skipping refresh');
        return; // Skip refresh if permission is denied
      }

      // Store currently selected contact identifiers to preserve selections
      final selectedIdentifiers =
          _selectedContacts.map((contact) => contact.identifier).toSet();

      Logger.info(
          '📋 Preserving ${selectedIdentifiers.length} contact selections');

      // Load fresh contacts from device
      final contacts = await ContactsService.getContacts(withThumbnails: false);
      final contactsList = contacts.where((contact) {
        return contact.displayName != null && contact.displayName!.isNotEmpty;
      }).toList();

      // Rebuild selected contacts based on fresh contact data
      final newSelectedContacts = <Contact>[];

      for (var contact in contactsList) {
        if (selectedIdentifiers.contains(contact.identifier)) {
          newSelectedContacts.add(contact);
          Logger.info('  ✅ Restored contact selection: ${contact.displayName}');
        }
      }

      setState(() {
        _allContacts = contactsList;
        _selectedContacts = newSelectedContacts;
      });

      Logger.info(
          '✅ Contacts refreshed: ${contactsList.length} total, ${newSelectedContacts.length} selected');
    } catch (e) {
      Logger.info('❌ Error refreshing contacts: $e');
    }
  }

  Future<void> _loadContacts() async {
    try {
      Logger.info('🔍 Loading contacts...');

      // Try to access contacts directly to test if permission is actually working
      try {
        await ContactsService.getContacts(withThumbnails: false);
        Logger.info('✅ Contacts access successful, permission is working');
      } catch (e) {
        Logger.info('❌ Contacts access failed: $e');

        // Check permission status and request if needed
        final permissionStatus = await Permission.contacts.status;
        Logger.info('🔐 Contacts permission status: $permissionStatus');

        if (permissionStatus.isDenied) {
          Logger.info('🔐 Requesting contacts permission...');
          final result = await Permission.contacts.request();
          Logger.info('🔐 Permission request result: $result');

          if (result.isDenied || result.isPermanentlyDenied) {
            setState(() {
              _errorMessage =
                  'Contacts permission is required to create groups';
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

      final contacts = await ContactsService.getContacts(withThumbnails: false);
      final contactsList = contacts.where((contact) {
        return contact.displayName != null && contact.displayName!.isNotEmpty;
      }).toList();

      setState(() {
        _allContacts = contactsList;
        _loading = false;
        Logger.info('📱 Loaded ${_allContacts.length} contacts');
        if (_allContacts.isEmpty) {
          _errorMessage = 'No contacts found';
        }
      });

      // If editing an existing group, select the contacts that are still available
      if (widget.group != null) {
        _selectExistingGroupContacts();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Error loading contacts: $e';
      });
    }
  }

  void _selectExistingGroupContacts() {
    if (widget.group == null) return;

    // Find contacts from the group that still exist in the current contact list
    final existingContacts = widget.group!.contacts.where((groupContact) {
      return _allContacts.any((deviceContact) =>
          deviceContact.identifier == groupContact.identifier);
    }).toList();

    setState(() {
      _selectedContacts = existingContacts;
    });

    Logger.info(
        '📱 Selected ${_selectedContacts.length} existing contacts for editing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? 'Create Group' : 'Edit Group'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
            onPressed: (_nameController.text.isNotEmpty &&
                    _selectedContacts.isNotEmpty)
                ? () {
                    final group = ContactGroup(
                      id: widget.group?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      name: _nameController.text,
                      contacts: _selectedContacts,
                    );
                    Navigator.pop(context, group);
                  }
                : null,
            child: Text('Save',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (_nameController.text.isNotEmpty &&
                          _selectedContacts.isNotEmpty)
                      ? const Color(0xFF007AFF)
                      : const Color(0xFF8E8E93),
                )),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: CupertinoTextField(
              controller: _nameController,
              placeholder: 'Group Name',
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${_selectedContacts.length} contacts selected',
              style: const TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          Expanded(
            child: _loading
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
                                style:
                                    const TextStyle(color: Color(0xFF8E8E93))),
                            if (_errorMessage.contains('permission'))
                              const Padding(
                                padding: EdgeInsets.only(top: 16),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _allContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _allContacts[index];
                          final isSelected = _selectedContacts
                              .any((c) => _contactsMatch(c, contact));

                          return ListTile(
                            title: Text(contact.displayName ?? 'Unknown'),
                            subtitle: Text(
                              contact.phones?.isNotEmpty == true
                                  ? contact.phones!.first.value ?? ''
                                  : 'No phone number',
                              style: const TextStyle(color: Color(0xFF8E8E93)),
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: Color(0xFF007AFF))
                                : const Icon(CupertinoIcons.circle,
                                    color: Color(0xFFD1D1D6)),
                            onTap: () {
                              try {
                                setState(() {
                                  if (isSelected) {
                                    _selectedContacts.removeWhere(
                                        (c) => _contactsMatch(c, contact));
                                  } else {
                                    _selectedContacts.add(contact);
                                  }
                                });
                                Logger.info(
                                    '📱 Contact ${contact.displayName} ${isSelected ? 'removed from' : 'added to'} selection');
                              } catch (e) {
                                Logger.info('❌ Error selecting contact: $e');
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  bool _contactsMatch(Contact contact1, Contact contact2) {
    // Compare by display name and phone number since identifiers might differ
    if (contact1.displayName != contact2.displayName) return false;

    final phone1 = contact1.phones?.isNotEmpty == true
        ? contact1.phones!.first.value
        : null;
    final phone2 = contact2.phones?.isNotEmpty == true
        ? contact2.phones!.first.value
        : null;

    return phone1 == phone2;
  }
}
