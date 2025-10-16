import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:contacts_service/contacts_service.dart';
import '../models/contact_group.dart';
import '../models/message_template.dart';
import '../models/message.dart';

class StorageService {
  static const String _groupsKey = 'contact_groups';
  static const String _templatesKey = 'message_templates';
  static const String _messagesKey = 'messages';
  static const String _sendAsIndividualKey = 'send_as_individual';

  // Save send type preference (true = individual, false = group)
  static Future<void> saveSendAsIndividual(bool sendAsIndividual) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sendAsIndividualKey, sendAsIndividual);
  }

  // Load send type preference (defaults to false = group)
  static Future<bool> loadSendAsIndividual() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sendAsIndividualKey) ?? false;
  }

  // Save groups to storage
  static Future<void> saveGroups(List<ContactGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    final groupsJson = groups
        .map((group) => {
              'id': group.id,
              'name': group.name,
              'contacts': group.contacts
                  .map((contact) => {
                        'identifier': contact.identifier,
                        'displayName': contact.displayName,
                        'phones': contact.phones
                            ?.map((phone) => {
                                  'value': phone.value,
                                  'label': phone.label,
                                })
                            .toList(),
                        'emails': contact.emails
                            ?.map((email) => {
                                  'value': email.value,
                                  'label': email.label,
                                })
                            .toList(),
                      })
                  .toList(),
            })
        .toList();

    await prefs.setString(_groupsKey, jsonEncode(groupsJson));
    print('💾 Saved ${groups.length} groups to storage');
  }

  // Load groups from storage
  static Future<List<ContactGroup>> loadGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final groupsJsonString = prefs.getString(_groupsKey);

      if (groupsJsonString == null) {
        print('📱 No groups found in storage');
        return [];
      }
      final groupsJson = jsonDecode(groupsJsonString) as List;
      final groups = groupsJson.map((groupData) {
        final contacts = (groupData['contacts'] as List).map((contactData) {
          final phones = contactData['phones'] != null
              ? (contactData['phones'] as List).map((phoneData) {
                  return Item(
                    value: phoneData['value'],
                    label: phoneData['label'],
                  );
                }).toList()
              : null;

          final emails = contactData['emails'] != null
              ? (contactData['emails'] as List).map((emailData) {
                  return Item(
                    value: emailData['value'],
                    label: emailData['label'],
                  );
                }).toList()
              : null;

          return Contact(
            displayName: contactData['displayName'],
            phones: phones,
            emails: emails,
          );
        }).toList();

        return ContactGroup(
          id: groupData['id'],
          name: groupData['name'],
          contacts: contacts,
        );
      }).toList();

      print('📱 Loaded ${groups.length} groups from storage');
      return groups;
    } catch (e) {
      print('❌ Error loading groups: $e');
      return [];
    }
  }

  // Validate and clean up groups by removing deleted contacts and updating renamed ones
  static Future<List<ContactGroup>> validateAndCleanGroups(
      List<ContactGroup> groups) async {
    try {
      print('📋 Validating and updating contacts from device...');
      print('📋 Groups to validate: ${groups.length}');

      // Try to access contacts directly to test if permission is actually working
      try {
        await ContactsService.getContacts(withThumbnails: false);
        print('✅ Contacts access successful, permission is working');
      } catch (e) {
        print('❌ Contacts access failed, skipping validation: $e');
        return groups; // Return groups as-is without validation
      }

      final deviceContacts =
          await ContactsService.getContacts(withThumbnails: false);
      print('📋 Device contacts loaded: ${deviceContacts.length}');

      bool hasChanges = false;
      final cleanedGroups = groups.map((group) {
        print(
            '📋 Validating group: ${group.name} with ${group.contacts.length} contacts');
        final validContacts = <Contact>[];

        for (final storedContact in group.contacts) {
          final storedPhone = storedContact.phones?.isNotEmpty == true
              ? normalizePhone(storedContact.phones!.first.value)
              : 'none';
          print(
              '  🔍 Checking stored contact: "${storedContact.displayName}" (phone: $storedPhone)');

          // Match by phone number (which doesn't change when contact is renamed)
          Contact? currentContact = deviceContacts.cast<Contact?>().firstWhere(
                (c) => c != null && _contactsMatch(c, storedContact),
                orElse: () => null,
              );

          if (currentContact != null) {
            // Use the fresh device contact to get updated name
            validContacts.add(currentContact);

            // Check if name changed
            if (currentContact.displayName != storedContact.displayName) {
              print(
                  '  ✅ Contact renamed: "${storedContact.displayName}" → "${currentContact.displayName}"');
              hasChanges = true;
            } else {
              print('  ✅ Contact matched: "${currentContact.displayName}"');
            }
          } else {
            print(
                '  ❌ No match found for: "${storedContact.displayName}" - will be removed');
            hasChanges = true;
          }
        }

        print(
            '📋 Group "${group.name}" validated: ${validContacts.length} valid contacts');
        return ContactGroup(
          id: group.id,
          name: group.name,
          contacts: validContacts,
        );
      }).toList();

      if (hasChanges) {
        await saveGroups(cleanedGroups);
        print('🧹 Updated groups with fresh contact data and saved to storage');
      } else {
        print('✅ No changes detected - contacts are up to date');
      }

      return cleanedGroups;
    } catch (e) {
      print('❌ Error validating groups: $e');
      return groups; // Return original groups if validation fails
    }
  }

  // Normalize phone number for comparison (remove formatting)
  static String normalizePhone(String? phone) {
    if (phone == null) return '';
    // Remove all non-digit characters except + at the start
    String normalized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    // If it starts with +, keep it, otherwise remove all +
    if (!normalized.startsWith('+')) {
      normalized = normalized.replaceAll('+', '');
    }
    return normalized;
  }

  // Helper method to match contacts by phone number (ignores name for rename detection)
  static bool _contactsMatch(Contact contact1, Contact contact2) {
    // Match by phone number only - names can change when contact is renamed
    // Check all phone numbers from both contacts for a match
    if (contact1.phones == null ||
        contact1.phones!.isEmpty ||
        contact2.phones == null ||
        contact2.phones!.isEmpty) {
      return false;
    }

    // Normalize and collect all phone numbers from both contacts
    final phones1 = contact1.phones!
        .map((p) => normalizePhone(p.value))
        .where((p) => p.isNotEmpty)
        .toSet();
    final phones2 = contact2.phones!
        .map((p) => normalizePhone(p.value))
        .where((p) => p.isNotEmpty)
        .toSet();

    // Check if any phone number matches
    final hasMatch = phones1.intersection(phones2).isNotEmpty;

    if (hasMatch) {
      print(
          '    📞 Phone match found: ${phones1.first} matches ${phones2.first}');
    }

    return hasMatch;
  }

  // Save templates to storage
  static Future<void> saveTemplates(List<MessageTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    final templatesJson = templates
        .map((template) => {
              'id': template.id,
              'name': template.name,
              'content': template.content,
            })
        .toList();

    await prefs.setString(_templatesKey, jsonEncode(templatesJson));
    print('💾 Saved ${templates.length} templates to storage');
  }

  // Load templates from storage
  static Future<List<MessageTemplate>> loadTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templatesJsonString = prefs.getString(_templatesKey);

      if (templatesJsonString == null) {
        print('📱 No templates found in storage');
        return [];
      }
      final templatesJson = jsonDecode(templatesJsonString) as List;
      final templates = templatesJson.map((templateData) {
        return MessageTemplate(
          id: templateData['id'],
          name: templateData['name'],
          content: templateData['content'],
        );
      }).toList();

      print('📱 Loaded ${templates.length} templates from storage');
      return templates;
    } catch (e) {
      print('❌ Error loading templates: $e');
      return [];
    }
  }

  // Save messages to storage
  static Future<void> saveMessages(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = messages
        .map((message) => {
              'id': message.id,
              'content': message.content,
              'timestamp': message.timestamp.millisecondsSinceEpoch,
              'isFromMe': message.isFromMe,
              'contactId': message.contactId,
              'groupId': message.groupId,
              'status': message.status.index,
              'type': message.type.index,
            })
        .toList();

    await prefs.setString(_messagesKey, jsonEncode(messagesJson));
    print('💾 Saved ${messages.length} messages to storage');
  }

  // Load messages from storage
  static Future<List<Message>> loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJsonString = prefs.getString(_messagesKey);

      if (messagesJsonString == null) {
        print('📱 No messages found in storage');
        return [];
      }
      final messagesJson = jsonDecode(messagesJsonString) as List;
      final messages = messagesJson.map((messageData) {
        // Safely handle status enum with fallback
        MessageStatus status;
        try {
          final statusIndex = messageData['status'] as int;
          if (statusIndex >= 0 && statusIndex < MessageStatus.values.length) {
            status = MessageStatus.values[statusIndex];
          } else {
            print('⚠️ Invalid status index $statusIndex, defaulting to sent');
            status = MessageStatus.sent;
          }
        } catch (e) {
          print('⚠️ Error parsing status, defaulting to sent: $e');
          status = MessageStatus.sent;
        }

        // Safely handle type enum with fallback
        MessageType type;
        try {
          if (messageData['type'] != null) {
            final typeIndex = messageData['type'] as int;
            if (typeIndex >= 0 && typeIndex < MessageType.values.length) {
              type = MessageType.values[typeIndex];
            } else {
              print('⚠️ Invalid type index $typeIndex, defaulting to group');
              type = MessageType.group;
            }
          } else {
            type = MessageType
                .group; // Default to group for backward compatibility
          }
        } catch (e) {
          print('⚠️ Error parsing type, defaulting to group: $e');
          type = MessageType.group;
        }

        return Message(
          id: messageData['id'],
          content: messageData['content'],
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(messageData['timestamp']),
          isFromMe: messageData['isFromMe'],
          contactId: messageData['contactId'],
          groupId: messageData['groupId'],
          status: status,
          type: type,
        );
      }).toList();

      print('📱 Loaded ${messages.length} messages from storage');
      return messages;
    } catch (e) {
      print('❌ Error loading messages: $e');
      return [];
    }
  }
}
