class RecipientInfo {
  final String id;
  final String displayName;
  final String? phoneNumber;
  final String? email;
  final String contactType; // 'phone' or 'email'
  final DateTime createdAt;

  RecipientInfo({
    required this.id,
    required this.displayName,
    this.phoneNumber,
    this.email,
    required this.contactType,
    required this.createdAt,
  });

  // Create from ContactInfo
  factory RecipientInfo.fromContactInfo(
      dynamic contactInfo, String contactType) {
    return RecipientInfo(
      id: '${contactInfo.contact.displayName}_${contactInfo.value}',
      displayName: contactInfo.contact.displayName ?? 'Unknown',
      phoneNumber: contactType == 'phone' ? contactInfo.value : null,
      email: contactType == 'email' ? contactInfo.value : null,
      contactType: contactType,
      createdAt: DateTime.now(),
    );
  }

  // Convert to Map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'email': email,
      'contactType': contactType,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  // Create from Map (for loading from storage)
  factory RecipientInfo.fromMap(Map<String, dynamic> map) {
    return RecipientInfo(
      id: map['id'],
      displayName: map['displayName'],
      phoneNumber: map['phoneNumber'],
      email: map['email'],
      contactType: map['contactType'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecipientInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
