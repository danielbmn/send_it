import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:contacts_service/contacts_service.dart';
// import 'package:url_launcher/url_launcher.dart'; // COMMENTED OUT - NO INVITE FUNCTIONALITY
import '../models/contact_info.dart';
import '../services/server_service.dart';

// Contact list item widget with always-visible phone/email details
class ExpandableContactTile extends StatelessWidget {
  final Contact contact;
  final Set<ContactInfo> selectedContactInfos;
  final Function(ContactInfo, bool) onContactInfoToggle;
  final bool showCheckboxes;

  const ExpandableContactTile({
    Key? key,
    required this.contact,
    required this.selectedContactInfos,
    required this.onContactInfoToggle,
    this.showCheckboxes = true,
  }) : super(key: key);

  List<ContactInfo> _getContactInfoList() {
    final List<ContactInfo> infos = [];

    // Add phone numbers (filter out fax)
    if (contact.phones != null) {
      for (var phone in contact.phones!) {
        if (phone.value != null && phone.value!.isNotEmpty) {
          // Filter out fax numbers
          final label = phone.label?.toLowerCase() ?? '';
          if (!label.contains('fax')) {
            infos.add(ContactInfo(
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
          infos.add(ContactInfo(
            contact: contact,
            value: email.value!,
            type: ContactInfoType.email,
            label: email.label,
          ));
        }
      }
    }

    return infos;
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

  @override
  Widget build(BuildContext context) {
    final contactInfos = _getContactInfoList();
    final isOnServer = ServerService.isContactOnServer(contact);
    final hasContactInfos = contactInfos.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Contact header
        ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                      border: Border.all(color: Colors.white, width: 2),
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
              // if (!isOnServer && hasContactInfos) ...[
              //   SizedBox(width: 8),
              //   CupertinoButton(
              //     padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              //     minSize: 0,
              //     color: Color(0xFF34C759),
              //     borderRadius: BorderRadius.circular(8),
              //     child: Text('Invite', style: TextStyle(fontSize: 11)),
              //     onPressed: () => _sendInvite(context, contact),
              //   ),
              // ],
            ],
          ),
          subtitle: !hasContactInfos
              ? Text(
                  'No phone or email',
                  style: TextStyle(
                    color: Color(0xFFFF9500),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : null,
        ),
        // Always show contact info details (phones and emails)
        if (hasContactInfos)
          ...contactInfos.map((info) {
            final isSelected = selectedContactInfos.contains(info);
            return Container(
              color: Color(0xFFF9F9F9),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity(horizontal: 0, vertical: -4),
                contentPadding:
                    EdgeInsets.only(left: 72, right: 16, top: 0, bottom: 0),
                minVerticalPadding: 0,
                leading: Icon(
                  info.labelIcon,
                  color: Color(0xFF8E8E93),
                  size: 16,
                ),
                title: Text(
                  info.displayValue,
                  style: TextStyle(fontSize: 14),
                ),
                trailing: showCheckboxes
                    ? Icon(
                        isSelected
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color:
                            isSelected ? Color(0xFF007AFF) : Color(0xFFD1D1D6),
                        size: 20,
                      )
                    : null,
                onTap: showCheckboxes
                    ? () {
                        onContactInfoToggle(info, !isSelected);
                      }
                    : null,
              ),
            );
          }).toList(),
      ],
    );
  }
}
