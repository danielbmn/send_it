import 'package:contacts_service/contacts_service.dart';

class ContactGroup {
  String id;
  String name;
  List<Contact> contacts;

  ContactGroup({required this.id, required this.name, required this.contacts});
}
