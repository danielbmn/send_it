import '../utils/helpers.dart';

class MessageTemplate {
  String id;
  String name;
  String content;

  MessageTemplate(
      {required this.id, required this.name, required this.content});

  // Check if template contains variables (like [First Name])
  bool hasVariables() {
    return Helpers.hasVariables(content);
  }
}
