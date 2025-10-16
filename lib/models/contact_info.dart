import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';

enum ContactInfoType { phone, email }

// Represents a specific contact method (phone or email) for selection
class ContactInfo {
  final Contact contact;
  final String value; // Phone number or email
  final ContactInfoType type;
  final String? label; // e.g., "mobile", "home", "work"

  ContactInfo({
    required this.contact,
    required this.value,
    required this.type,
    this.label,
  });

  String get displayValue => value;
  String get displayLabel =>
      label ?? (type == ContactInfoType.phone ? 'phone' : 'email');

  // Get icon for label type
  IconData get labelIcon {
    if (type == ContactInfoType.phone) {
      final lowerLabel = (label ?? '').toLowerCase();
      if (lowerLabel.contains('mobile') || lowerLabel.contains('cell')) {
        return CupertinoIcons.device_phone_portrait;
      } else if (lowerLabel.contains('home')) {
        return CupertinoIcons.house;
      } else if (lowerLabel.contains('work')) {
        return CupertinoIcons.briefcase;
      }
      return CupertinoIcons.phone;
    } else {
      final lowerLabel = (label ?? '').toLowerCase();
      if (lowerLabel.contains('home')) {
        return CupertinoIcons.house;
      } else if (lowerLabel.contains('work')) {
        return CupertinoIcons.briefcase;
      }
      return CupertinoIcons.mail;
    }
  }

  // Unique key for comparison
  String get key => '${contact.displayName}_${type.name}_$value';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContactInfo && other.key == key;
  }

  @override
  int get hashCode => key.hashCode;
}
