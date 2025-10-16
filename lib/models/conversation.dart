import 'package:contacts_service/contacts_service.dart';
import 'message.dart';

class Conversation {
  String id;
  String? name;
  List<Contact> contacts;
  List<Message> messages;
  DateTime lastMessageTime;
  String? lastMessagePreview;

  Conversation({
    required this.id,
    this.name,
    required this.contacts,
    required this.messages,
    required this.lastMessageTime,
    this.lastMessagePreview,
  });
}
