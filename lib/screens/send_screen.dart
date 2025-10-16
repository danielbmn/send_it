import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:flutter_sms/flutter_sms.dart';
import '../models/contact_group.dart';
import '../models/message_template.dart';
import '../services/storage_service.dart';

class SendScreen extends StatefulWidget {
  final List<ContactGroup> groups;
  final List<MessageTemplate> templates;

  SendScreen({required this.groups, required this.templates});

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
      print('🔄 Refreshing send screen data on app resume...');

      // Refresh groups and templates from storage
      await StorageService.loadGroups();
      await StorageService.loadTemplates();

      setState(() {
        // Update the widget's data by triggering a rebuild
        // The parent should have already refreshed, but this ensures consistency
      });

      print('✅ Send screen data refreshed');
    } catch (e) {
      print('❌ Error refreshing send screen data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Send Messages',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Group',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<ContactGroup>(
                      value: _selectedGroup,
                      isExpanded: true,
                      underline: SizedBox(),
                      hint: Text('Choose a group'),
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
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Template',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<MessageTemplate>(
                      value: _selectedTemplate,
                      isExpanded: true,
                      underline: SizedBox(),
                      hint: Text('Choose a template'),
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
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Preview',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 8),
                    Text(
                      _selectedTemplate!.content,
                      style: TextStyle(color: Color(0xFF3C3C43)),
                    ),
                  ],
                ),
              ),
            ],
            Spacer(),
            ElevatedButton(
              onPressed: _selectedGroup == null ||
                      _selectedTemplate == null ||
                      _sending
                  ? null
                  : _sendMessages,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF007AFF),
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _sending
                  ? CupertinoActivityIndicator(color: Colors.white)
                  : Text(
                      'Send Messages',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
            SizedBox(height: 20),
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
          print('❌ Empty message for ${contact.displayName}, skipping');
          failCount++;
          continue;
        }

        print('📝 Sending message to ${contact.displayName}: $message');

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
        print('❌ Failed to send to ${contact.displayName}: $e');
      }

      // Add small delay between messages to avoid rate limiting
      await Future.delayed(Duration(milliseconds: 500));
    }

    setState(() => _sending = false);

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Messages Sent'),
        content: Text('Successfully sent to $successCount contacts'
            '${failCount > 0 ? '\nFailed: $failCount' : ''}'),
        actions: [
          CupertinoDialogAction(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
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

    print('📝 Personalized message for ${contact.displayName}: $message');
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
    await Future.delayed(Duration(seconds: 1));
    print('Sent encrypted message to ${contact.displayName}: $message');
  }

  Future<void> _sendSMS(Contact contact, String message) async {
    if (contact.phones?.isNotEmpty != true) {
      throw Exception('No phone number for contact');
    }

    final phoneNumber = contact.phones!.first.value!;

    // Clean the phone number - remove any formatting
    final cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    print('📱 Sending SMS to $cleanPhoneNumber: $message');

    try {
      // Use the native SMS composer with pre-filled recipient and message
      String result = await sendSMS(
        message: message,
        recipients: [cleanPhoneNumber],
        sendDirect: false, // This will open the native SMS composer
      );

      print('✅ SMS composer opened successfully: $result');
    } catch (e) {
      print('❌ Error opening SMS composer: $e');
      throw Exception('Could not open SMS composer: $e');
    }
  }
}
