import 'package:contacts_service/contacts_service.dart';

class ServerService {
  // COMMENTED OUT FOR RELEASE - NO BACKEND SERVER
  // static final Map<String, bool> _serverContacts = {};
  // static bool _firstContactAssigned = false;

  // COMMENTED OUT FOR RELEASE - ALL CONTACTS ARE NATIVE SMS
  // Simulate backend server - only first contact is on server
  static bool isContactOnServer(Contact contact) {
    // FOR RELEASE: All contacts are native SMS users
    return false;

    // COMMENTED OUT - ORIGINAL SERVER LOGIC
    // // Use phone number only as key - this way server status persists even if contact is renamed
    // // In production, the server would match by phone number or user ID
    // final phoneNumber = contact.phones?.isNotEmpty == true
    //     ? contact.phones!.first.value ?? 'nophone'
    //     : 'nophone';
    // final contactKey = phoneNumber;

    // if (!_serverContacts.containsKey(contactKey)) {
    //   // Only assign the first contact to be on server
    //   if (!_firstContactAssigned) {
    //     _serverContacts[contactKey] = true;
    //     _firstContactAssigned = true;
    //     print(
    //         '🔍 Server assignment for ${contact.displayName} ($phoneNumber): Server (first contact)');
    //   } else {
    //     _serverContacts[contactKey] = false;
    //     print(
    //         '🔍 Server assignment for ${contact.displayName} ($phoneNumber): Native');
    //   }
    // }

    // final isServer = _serverContacts[contactKey] ?? false;
    // print(
    //     '🔍 Contact ${contact.displayName} ($phoneNumber): ${isServer ? 'Server' : 'Native'}');
    // return isServer;
  }

  // Get server status for display
  static String getServerStatus(Contact contact) {
    // FOR RELEASE: All contacts are native SMS
    return 'native';

    // COMMENTED OUT - ORIGINAL SERVER LOGIC
    // return isContactOnServer(contact) ? 'server' : 'native';
  }
}
