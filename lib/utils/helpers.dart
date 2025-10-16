import 'package:contacts_service/contacts_service.dart';
import '../models/contact_info.dart';

class Helpers {
  // Get contact names - first names only
  static String getContactNames(List<Contact> contacts) {
    if (contacts.isEmpty) return 'Unknown';
    // List all FIRST names only, separated by commas (will be faded at end by ShaderMask)
    return contacts.map((c) {
      final fullName = c.displayName ?? 'Unknown';
      // Extract first name (first word before space)
      return fullName.split(' ').first;
    }).join(', ');
  }

  // Format time for display
  static String formatTime(DateTime time) {
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

  // Helper method to match contacts by name and phone
  static bool contactsMatch(Contact contact1, Contact contact2) {
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

  // Extract all contact methods (phones and emails) from a list of contacts
  static List<ContactInfo> extractContactMethods(List<Contact> contacts) {
    final List<ContactInfo> allContactMethods = [];

    for (var contact in contacts) {
      // Add phone numbers (excluding fax)
      if (contact.phones != null) {
        for (var phone in contact.phones!) {
          if (phone.value != null && phone.value!.isNotEmpty) {
            final label = phone.label?.toLowerCase() ?? '';
            if (!label.contains('fax')) {
              allContactMethods.add(ContactInfo(
                contact: contact,
                value: phone.value!,
                type: ContactInfoType.phone,
                label: phone.label,
              ));
            }
          }
        }
      }

      // Add emails
      if (contact.emails != null) {
        for (var email in contact.emails!) {
          if (email.value != null && email.value!.isNotEmpty) {
            allContactMethods.add(ContactInfo(
              contact: contact,
              value: email.value!,
              type: ContactInfoType.email,
              label: email.label,
            ));
          }
        }
      }
    }

    return allContactMethods;
  }

  // Available template variables (must match create_template_screen.dart)
  static const List<String> templateVariables = [
    '[First Name]',
    '[Last Name]',
    '[Full Name]',
    '[Phone]',
  ];

  // Check if message content contains template variables
  static bool hasVariables(String content) {
    for (var variable in templateVariables) {
      if (content.contains(variable)) {
        return true;
      }
    }
    return false;
  }
}
