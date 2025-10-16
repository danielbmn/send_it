import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
// import 'package:contacts_service/contacts_service.dart'; // COMMENTED OUT - NO INVITE FUNCTIONALITY
// import 'package:url_launcher/url_launcher.dart'; // COMMENTED OUT - NO INVITE FUNCTIONALITY
import '../models/message.dart';
import '../models/contact_info.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';

// Stateful Recipients Screen for real-time status updates
class RecipientsScreen extends StatefulWidget {
  final Message message;
  final List<ContactInfo> allContactMethods;
  final Set<String>? originalRecipients;
  final Map<String, String>? recipientStatuses;
  final Function(ContactInfo, String, Message, Function()) onRetryRecipient;
  final Function(ContactInfo, String, bool, Message, Function())
      onRecipientAction;
  final Function(ContactInfo, Message, Function()) onSendToNew;
  final Function()? onStatusUpdate;
  final Function(String) getRecipientStatuses;

  const RecipientsScreen({
    Key? key,
    required this.message,
    required this.allContactMethods,
    required this.originalRecipients,
    required this.recipientStatuses,
    required this.onRetryRecipient,
    required this.onRecipientAction,
    required this.onSendToNew,
    this.onStatusUpdate,
    required this.getRecipientStatuses,
  }) : super(key: key);

  @override
  _RecipientsScreenState createState() => _RecipientsScreenState();
}

class _RecipientsScreenState extends State<RecipientsScreen> {
  Timer? _statusUpdateTimer;
  Message? _currentMessage;
  Map<String, String>? _currentRecipientStatuses;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.message;
    _currentRecipientStatuses = widget.recipientStatuses;
    _startStatusUpdateTimer();
  }

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    super.dispose();
  }

  void _startStatusUpdateTimer() {
    // Update status every 1 second to show real-time changes
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _refreshMessageStatus();
    });
  }

  Future<void> _refreshMessageStatus() async {
    try {
      // Load the latest message status from storage
      final messages = await StorageService.loadMessages();
      final latestMessage = messages.firstWhere(
        (m) => m.id == widget.message.id,
        orElse: () => widget.message,
      );

      // Get fresh recipient statuses from parent
      final freshRecipientStatuses =
          widget.getRecipientStatuses(widget.message.id);

      // Always update to get latest recipient statuses
      if (mounted) {
        setState(() {
          _currentMessage = latestMessage;
          _currentRecipientStatuses =
              freshRecipientStatuses ?? _currentRecipientStatuses;
        });
        print('🔄 RecipientsScreen refreshed with latest message status');
      }
    } catch (e) {
      print('❌ Error refreshing message status: $e');
    }
  }

  String _getMessageStatusForRecipient(ContactInfo method) {
    // Use current message for real-time updates
    final message = _currentMessage ?? widget.message;

    // Check per-recipient status first
    final recipientKey = '${method.contact.displayName}_${method.value}';
    final status = _currentRecipientStatuses?[recipientKey];
    if (status != null) {
      return status;
    }

    // Check if contact is on server
    final isOnServer = ServerService.isContactOnServer(method.contact);

    // For non-server contacts, show SMS status
    if (!isOnServer) {
      if (message.status == MessageStatus.sending) return 'Sending';
      if (message.status == MessageStatus.cancelled) return 'Cancelled';
      return 'SMS';
    }

    // For server contacts, default based on overall message status
    if (message.type == MessageType.individual) {
      if (message.status == MessageStatus.sending) {
        return 'Sending';
      }
      if (message.status == MessageStatus.failed) {
        return 'Failed';
      }
      if (message.status == MessageStatus.cancelled) {
        return 'Cancelled';
      }
      return 'Sent';
    }

    // For group messages, all recipients have same status
    if (message.status == MessageStatus.sending) return 'Sending';
    if (message.status == MessageStatus.sent) return 'Sent';
    if (message.status == MessageStatus.cancelled) return 'Cancelled';
    return 'Failed';
  }

  Widget _buildRecipientStatusBadge(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'Sending':
        color = Color(0xFF8E8E93);
        icon = CupertinoIcons.clock;
        break;
      case 'Sent':
        color = Color(0xFF34C759);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'SMS':
        color = Color(0xFF8E8E93);
        icon = CupertinoIcons.checkmark_circle;
        break;
      case 'New Recipient':
        color = Color(0xFF8E8E93);
        icon = CupertinoIcons.person_badge_plus;
        break;
      case 'Delivered':
        color = Color(0xFF5AC8FA);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Read':
        color = Color(0xFF007AFF);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Failed':
        color = Color(0xFFFF3B30);
        icon = CupertinoIcons.exclamationmark_circle_fill;
        break;
      case 'Cancelled':
        color = Color(0xFFFF9500);
        icon = CupertinoIcons.xmark_circle_fill;
        break;
      default:
        color = Color(0xFF8E8E93);
        icon = CupertinoIcons.circle;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Group contact methods by contact
    final Map<String, List<ContactInfo>> contactsMap = {};
    for (var method in widget.allContactMethods) {
      final contactName = method.contact.displayName ?? 'Unknown';
      if (!contactsMap.containsKey(contactName)) {
        contactsMap[contactName] = [];
      }
      contactsMap[contactName]!.add(method);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Recipients'),
        backgroundColor: Color(0xFFF9F9F9),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header with message type
          Container(
            padding: EdgeInsets.all(16),
            color: Color(0xFFF9F9F9),
            child: Row(
              children: [
                Icon(
                  (_currentMessage ?? widget.message).type == MessageType.group
                      ? CupertinoIcons.person_3
                      : CupertinoIcons.person,
                  color: Color(0xFF007AFF),
                ),
                SizedBox(width: 12),
                Text(
                  (_currentMessage ?? widget.message).type == MessageType.group
                      ? 'Group Message (Server)'
                      : 'Individual Messages (SMS)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1),
          // Recipients list
          Expanded(
            child: ListView.builder(
              itemCount: contactsMap.length,
              itemBuilder: (context, index) {
                final contactName = contactsMap.keys.elementAt(index);
                final contactMethods = contactsMap[contactName]!;
                final firstMethod = contactMethods.first;
                final contact = firstMethod.contact;
                final isOnServer = ServerService.isContactOnServer(contact);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact header
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0xFF007AFF),
                            child: Text(
                              (contact.displayName?.isNotEmpty == true
                                      ? contact.displayName![0]
                                      : '?')
                                  .toUpperCase(),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ),
                          if (isOnServer)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Color(0xFF007AFF),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: Icon(
                                  CupertinoIcons.checkmark,
                                  color: Colors.white,
                                  size: 8,
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Text(
                            contact.displayName ?? 'Unknown',
                            style: TextStyle(fontSize: 15),
                          ),
                          // COMMENTED OUT FOR RELEASE - NO BACKEND SERVER
                          // if (!isOnServer) ...[
                          //   SizedBox(width: 8),
                          //   CupertinoButton(
                          //     padding: EdgeInsets.symmetric(
                          //         horizontal: 8, vertical: 2),
                          //     minSize: 0,
                          //     color: Color(0xFF34C759),
                          //     borderRadius: BorderRadius.circular(8),
                          //     child: Text('Invite',
                          //         style: TextStyle(fontSize: 11)),
                          //     onPressed: () => _sendInvite(context, contact),
                          //   ),
                          // ],
                        ],
                      ),
                    ),
                    // Contact info details with status badges
                    ...contactMethods.map((method) {
                      // Check if this recipient was in the original message
                      final recipientKey =
                          '${method.contact.displayName}_${method.value}';
                      final isNewRecipient = widget.originalRecipients !=
                              null &&
                          !widget.originalRecipients!.contains(recipientKey);

                      final status = isNewRecipient
                          ? 'New Recipient'
                          : _getMessageStatusForRecipient(method);
                      final isFailed = status == 'Failed';
                      final isCancelled = status == 'Cancelled';

                      return GestureDetector(
                        onTap: (isFailed ||
                                isCancelled ||
                                !isOnServer ||
                                isNewRecipient)
                            ? () {
                                final currentMessage =
                                    _currentMessage ?? widget.message;
                                if (isNewRecipient) {
                                  widget.onSendToNew(method, currentMessage,
                                      () {
                                    setState(() {});
                                    widget.onStatusUpdate?.call();
                                  });
                                } else if (isFailed || isCancelled) {
                                  // Direct retry for failed or cancelled recipients
                                  // For group messages, this will retry the entire group
                                  // For individual messages, this will retry just this recipient
                                  widget.onRetryRecipient(
                                      method,
                                      currentMessage.content,
                                      currentMessage, () {
                                    setState(() {});
                                    widget.onStatusUpdate?.call();
                                  });
                                } else {
                                  // For non-server users, show the action dialog
                                  widget.onRecipientAction(
                                      method,
                                      currentMessage.content,
                                      isOnServer,
                                      currentMessage, () {
                                    setState(() {});
                                    widget.onStatusUpdate?.call();
                                  });
                                }
                              }
                            : null,
                        child: Container(
                          color: Color(0xFFF9F9F9),
                          child: ListTile(
                            dense: true,
                            visualDensity:
                                VisualDensity(horizontal: 0, vertical: -4),
                            contentPadding: EdgeInsets.only(
                                left: 72, right: 16, top: 0, bottom: 0),
                            minVerticalPadding: 0,
                            leading: Icon(
                              method.labelIcon,
                              color: Color(0xFF8E8E93),
                              size: 16,
                            ),
                            title: Text(
                              method.displayValue,
                              style: TextStyle(fontSize: 14),
                            ),
                            trailing: _buildRecipientStatusBadge(status),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // COMMENTED OUT FOR RELEASE - NO BACKEND SERVER
  // void _sendInvite(BuildContext context, Contact contact) async {
  //   final inviteMessage =
  //       'Join me on sendit! Download here: https://sendit.app/invite';

  //   // Get first phone number
  //   String? phoneNumber;
  //   if (contact.phones != null && contact.phones!.isNotEmpty) {
  //     phoneNumber = contact.phones!.first.value;
  //   }

  //   if (phoneNumber != null) {
  //     // Open native Messages app with invite pre-filled
  //     final smsUrl =
  //         'sms:$phoneNumber&body=${Uri.encodeComponent(inviteMessage)}';
  //     try {
  //       await launchUrl(Uri.parse(smsUrl));
  //     } catch (e) {
  //       print('❌ Error opening Messages app: $e');
  //     }
  //   }
  // }
}
