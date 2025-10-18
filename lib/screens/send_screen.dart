import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter_sms/flutter_sms.dart';
import '../models/contact_group.dart';
import '../models/message_template.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

class SendScreen extends StatefulWidget {
  final List<ContactGroup> groups;
  final List<MessageTemplate> templates;

  const SendScreen({super.key, required this.groups, required this.templates});

  @override
  _SendScreenState createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with WidgetsBindingObserver {
  ContactGroup? _selectedGroup;
  MessageTemplate? _selectedTemplate;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh data when app becomes active again
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    try {
      Logger.info('Refreshing send screen data on app resume...');

      // Refresh groups and templates from storage
      await StorageService.loadGroups();
      await StorageService.loadTemplates();

      setState(() {
        // Update the widget's data by triggering a rebuild
        // The parent should have already refreshed, but this ensures consistency
      });

      Logger.success('Send screen data refreshed');
    } catch (e) {
      Logger.error('Error refreshing send screen data', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Messages',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Group',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<ContactGroup>(
                      value: _selectedGroup,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text('Choose a group'),
                      items: widget.groups.map((group) {
                        return DropdownMenuItem(
                          value: group,
                          child: Text(group.name),
                        );
                      }).toList(),
                      onChanged: (group) =>
                          setState(() => _selectedGroup = group),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Template',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<MessageTemplate>(
                      value: _selectedTemplate,
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: const Text('Choose a template'),
                      items: widget.templates.map((template) {
                        return DropdownMenuItem(
                          value: template,
                          child: Text(template.name),
                        );
                      }).toList(),
                      onChanged: (template) =>
                          setState(() => _selectedTemplate = template),
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedTemplate != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Preview',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                      _selectedTemplate!.content,
                      style: const TextStyle(color: Color(0xFF3C3C43)),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            ElevatedButton(
              onPressed: _selectedGroup == null ||
                      _selectedTemplate == null ||
                      _sending
                  ? null
                  : _sendMessages,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _sending
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                      'Send Messages',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessages() async {
    if (_selectedGroup == null || _selectedTemplate == null) return;

    setState(() => _sending = true);

    int successCount = 0;
    int failCount = 0;

    for (var contact in _selectedGroup!.contacts) {
      try {
        String message =
            _personalizeMessage(_selectedTemplate!.content, contact);

        // Validate message is not empty
        if (message.trim().isEmpty) {
          Logger.warning('Empty message for ${contact.displayName}, skipping');
          failCount++;
          continue;
        }

        Logger.info('Sending message to ${contact.displayName}: $message');

        // Check if recipient has the app (this is a placeholder - you'd implement actual logic)
        bool hasApp = await _checkIfUserHasApp(contact);

        if (hasApp) {
          // Send encrypted message through app
          await _sendEncryptedMessage(contact, message);
        } else {
          // Open native SMS with prepopulated message
          await _sendSMS(contact, message);
        }

        successCount++;
      } catch (e) {
        failCount++;
        Logger.error('Failed to send to ${contact.displayName}', e);
      }

      // Add small delay between messages to avoid rate limiting
      await Future.delayed(const Duration(milliseconds: 500));
    }

    setState(() => _sending = false);

    if (mounted) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Messages Sent'),
          content: Text('Successfully sent to $successCount contacts'
              '${failCount > 0 ? '\nFailed: $failCount' : ''}'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    }
  }

  String _personalizeMessage(String template, Contact contact) {
    String message = template;

    // Replace variables with actual contact data
    String firstName = '';
    String lastName = '';
    String fullName = contact.displayName ?? '';

    if (fullName.isNotEmpty) {
      List<String> nameParts = fullName.split(' ');
      firstName = nameParts.first;
      if (nameParts.length > 1) {
        lastName = nameParts.sublist(1).join(' ');
      }
    }

    String phoneNumber = '';
    if (contact.phones?.isNotEmpty == true) {
      phoneNumber = contact.phones!.first.value ?? '';
    }

    message = message.replaceAll('[First Name]', firstName);
    message = message.replaceAll('[Last Name]', lastName);
    message = message.replaceAll('[Full Name]', fullName);
    message = message.replaceAll('[Phone]', phoneNumber);

    Logger.info('Personalized message for ${contact.displayName}: $message');
    return message;
  }

  Future<bool> _checkIfUserHasApp(Contact contact) async {
    // This is a placeholder implementation
    // In a real app, you would check your backend to see if this phone number
    // is registered with your app

    // For demo purposes, randomly return true/false
    return Future.value(DateTime.now().millisecondsSinceEpoch % 3 == 0);
  }

  Future<void> _sendEncryptedMessage(Contact contact, String message) async {
    // This is a placeholder for sending encrypted messages through your app
    // You would implement your actual encrypted messaging logic here

    // For demo purposes, just simulate sending
    await Future.delayed(const Duration(seconds: 1));
    Logger.info('Sent encrypted message to ${contact.displayName}: $message');
  }

  Future<void> _sendSMS(Contact contact, String message) async {
    if (contact.phones?.isNotEmpty != true) {
      throw Exception('No phone number for contact');
    }

    final phoneNumber = contact.phones!.first.value!;

    // Clean the phone number - remove any formatting
    final cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    Logger.info('Sending SMS to $cleanPhoneNumber: $message');

    try {
      // Use the native SMS composer with pre-filled recipient and message
      String result = await sendSMS(
        message: message,
        recipients: [cleanPhoneNumber],
        sendDirect: false, // This will open the native SMS composer
      );

      Logger.success('SMS composer opened successfully: $result');
    } catch (e) {
      Logger.error('Error opening SMS composer', e);
      throw Exception('Could not open SMS composer: $e');
    }
  }
}
