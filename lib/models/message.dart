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

  Message({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.isFromMe,
    this.contactId,
    this.groupId,
    this.status = MessageStatus.sending,
    this.type = MessageType.group,
  });
}
