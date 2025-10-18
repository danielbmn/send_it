import 'recipient_info.dart';

enum MessageStatus { sending, sent, failed, cancelled }

enum MessageType { group, individual }

class Message {
  String id;
  String content;
  DateTime timestamp;
  bool isFromMe;
  String? contactId;
  String? groupId;
  MessageStatus status;
  MessageType type;

  // Store complete recipient history - never remove entries
  Map<String, String> recipientHistory; // recipientKey -> status
  DateTime? historyExpiry; // When this message history should expire

  // Store original recipients (preserved even if contacts are removed)
  List<RecipientInfo> originalRecipients;

  Message({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.isFromMe,
    this.contactId,
    this.groupId,
    this.status = MessageStatus.sending,
    this.type = MessageType.group,
    Map<String, String>? recipientHistory,
    this.historyExpiry,
    List<RecipientInfo>? originalRecipients,
  })  : recipientHistory = recipientHistory ?? {},
        originalRecipients = originalRecipients ?? [];
}
