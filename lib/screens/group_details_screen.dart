import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/contact_group.dart';

class GroupDetailsScreen extends StatelessWidget {
  final ContactGroup group;

  GroupDetailsScreen({required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: group.contacts.length,
        itemBuilder: (context, index) {
          final contact = group.contacts[index];
          return Container(
            margin: EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFF007AFF),
                child: Text(
                  (contact.displayName?.isNotEmpty == true
                          ? contact.displayName![0]
                          : '?')
                      .toUpperCase(),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              title: Text(contact.displayName ?? 'Unknown'),
              subtitle: Text(
                contact.phones?.isNotEmpty == true
                    ? contact.phones!.first.value ?? 'No number'
                    : 'No number',
                style: TextStyle(color: Color(0xFF8E8E93)),
              ),
            ),
          );
        },
      ),
    );
  }
}
