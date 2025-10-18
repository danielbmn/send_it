import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import '../utils/logger.dart';
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
    super.key,
    required this.message,
    required this.allContactMethods,
    required this.originalRecipients,
    required this.recipientStatuses,
    required this.onRetryRecipient,
    required this.onRecipientAction,
    required this.onSendToNew,
    this.onStatusUpdate,
    required this.getRecipientStatuses,
  });

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
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
        Logger.info('RecipientsScreen refreshed with latest message status');
      }
    } catch (e) {
      Logger.error('Error refreshing message status', e);
    }
  }

  /* String _getMessageStatusForRecipient(ContactInfo method) {
    // Use current message for real-time updates
    final message = _currentMessage ?? widget.message;

    // Check message's recipient history first (persistent across group changes)
    final recipientKey = '${method.contact.displayName}_${method.value}';
    final status = message.recipientHistory[recipientKey];
    if (status != null) {
      return status;
    }

    // Fallback to current recipient statuses for backward compatibility
    final oldStatus = _currentRecipientStatuses?[recipientKey];
    if (oldStatus != null) {
      return oldStatus;
    }

    // Check if contact is on server
    final isOnServer = ServerService.isContactOnServer(method.contact);

    // For non-server contacts, show SMS status
    // If no specific status found, default to "SMS" (gray) indicating we sent it via native SMS
    if (!isOnServer) {
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
  } */

  Widget _buildRecipientStatusBadge(String status) {
    Color color;
    IconData icon;

    switch (status) {
      case 'Sending':
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.clock;
        break;
      case 'Sent':
        color = const Color(0xFF34C759);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'SMS':
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.checkmark_circle;
        break;
      case 'Email':
        color = const Color(0xFF007AFF);
        icon = CupertinoIcons.mail;
        break;
      case 'New Recipient':
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.person_badge_plus;
        break;
      case 'Delivered':
        color = const Color(0xFF5AC8FA);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Read':
        color = const Color(0xFF007AFF);
        icon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'Failed':
        color = const Color(0xFFFF3B30);
        icon = CupertinoIcons.exclamationmark_circle_fill;
        break;
      case 'Cancelled':
        color = const Color(0xFFFF9500);
        icon = CupertinoIcons.xmark_circle_fill;
        break;
      default:
        color = const Color(0xFF8E8E93);
        icon = CupertinoIcons.circle;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
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

  List<Map<String, dynamic>> _buildAllRecipientsList() {
    final message = _currentMessage ?? widget.message;
    final allRecipients = <Map<String, dynamic>>[];

    // Always use original recipients from message (preserved even if contacts are removed)
    for (var recipientInfo in message.originalRecipients) {
      final contactValue = recipientInfo.contactType == 'phone'
          ? recipientInfo.phoneNumber!
          : recipientInfo.email!;
      final recipientKey = '${recipientInfo.displayName}_$contactValue';
      final status = message.recipientHistory[recipientKey] ??
          (recipientInfo.contactType == 'phone' ? 'SMS' : 'Email');

      // Create a mock ContactInfo for the recipient
      final method = ContactInfo(
        contact: Contact(
          displayName: recipientInfo.displayName,
          phones: recipientInfo.phoneNumber != null
              ? [Item(label: 'mobile', value: recipientInfo.phoneNumber!)]
              : null,
          emails: recipientInfo.email != null
              ? [Item(label: 'email', value: recipientInfo.email!)]
              : null,
        ),
        type: recipientInfo.contactType == 'phone'
            ? ContactInfoType.phone
            : ContactInfoType.email,
        value: contactValue,
      );

      // Check if this recipient is still in the current group
      final isInCurrentGroup = widget.allContactMethods.any((currentMethod) =>
          currentMethod.contact.displayName == recipientInfo.displayName &&
          currentMethod.value == contactValue);

      allRecipients.add({
        'method': method,
        'status': status,
        'isHistorical': !isInCurrentGroup,
      });
    }

    return allRecipients;
  }

  @override
  Widget build(BuildContext context) {
    // Build recipients from message history + current contacts
    final allRecipients = _buildAllRecipientsList();

    // Group contact methods by contact
    final Map<String, List<ContactInfo>> contactsMap = {};
    for (var recipient in allRecipients) {
      final method = recipient['method'] as ContactInfo;
      final contactName = method.contact.displayName ?? 'Unknown';
      if (!contactsMap.containsKey(contactName)) {
        contactsMap[contactName] = [];
      }
      contactsMap[contactName]!.add(method);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipients'),
        backgroundColor: const Color(0xFFF9F9F9),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Header with message type
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFF9F9F9),
            child: Row(
              children: [
                Icon(
                  (_currentMessage ?? widget.message).type == MessageType.group
                      ? CupertinoIcons.person_3
                      : CupertinoIcons.person,
                  color: const Color(0xFF007AFF),
                ),
                const SizedBox(width: 12),
                Text(
                  (_currentMessage ?? widget.message).type == MessageType.group
                      ? 'Group Message (Server)'
                      : 'Individual Messages (SMS)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Recipients list
          Expanded(
            child: ListView.builder(
              itemCount: allRecipients.length,
              itemBuilder: (context, index) {
                final recipient = allRecipients[index];
                final method = recipient['method'] as ContactInfo;
                final status = recipient['status'] as String;
                final isHistorical = recipient['isHistorical'] as bool;
                final contact = method.contact;
                final isOnServer = ServerService.isContactOnServer(contact);

                // Check if this recipient was in the original message
                final recipientKey =
                    '${method.contact.displayName}_${method.value}';
                final isNewRecipient = widget.originalRecipients != null &&
                    !widget.originalRecipients!.contains(recipientKey);

                final finalStatus = isNewRecipient ? 'New Recipient' : status;
                final isFailed = finalStatus == 'Failed';
                final isCancelled = finalStatus == 'Cancelled';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Contact header
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF007AFF),
                            child: Text(
                              (contact.displayName?.isNotEmpty == true
                                      ? contact.displayName![0]
                                      : '?')
                                  .toUpperCase(),
                              style: const TextStyle(
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
                                  color: const Color(0xFF007AFF),
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(
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
                            style: TextStyle(
                              fontSize: 15,
                              color: isHistorical ? Colors.grey[600] : null,
                            ),
                          ),
                          if (isHistorical) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Removed',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Contact info details with status badges
                    GestureDetector(
                      onTap: (isFailed ||
                              isCancelled ||
                              !isOnServer ||
                              isNewRecipient)
                          ? () {
                              final currentMessage =
                                  _currentMessage ?? widget.message;
                              if (isNewRecipient) {
                                widget.onSendToNew(method, currentMessage, () {
                                  setState(() {});
                                  widget.onStatusUpdate?.call();
                                });
                              } else if (isFailed || isCancelled) {
                                // Direct retry for failed or cancelled recipients
                                // For group messages, this will retry the entire group
                                // For individual messages, this will retry just this recipient
                                widget.onRetryRecipient(method,
                                    currentMessage.content, currentMessage, () {
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
                        color: const Color(0xFFF9F9F9),
                        child: ListTile(
                          dense: true,
                          visualDensity:
                              const VisualDensity(horizontal: 0, vertical: -4),
                          contentPadding: const EdgeInsets.only(
                              left: 72, right: 16, top: 0, bottom: 0),
                          minVerticalPadding: 0,
                          leading: Icon(
                            method.labelIcon,
                            color: const Color(0xFF8E8E93),
                            size: 16,
                          ),
                          title: Text(
                            method.displayValue,
                            style: const TextStyle(fontSize: 14),
                          ),
                          trailing: _buildRecipientStatusBadge(finalStatus),
                        ),
                      ),
                    ),
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
