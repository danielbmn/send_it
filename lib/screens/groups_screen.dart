import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../models/contact_group.dart';
import '../services/storage_service.dart';
import 'create_group_screen.dart';
import 'group_details_screen.dart';

class GroupsScreen extends StatefulWidget {
  final List<ContactGroup> groups;
  final Function(List<ContactGroup>) onGroupsChanged;

  GroupsScreen({required this.groups, required this.onGroupsChanged});

  @override
  _GroupsScreenState createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with WidgetsBindingObserver {
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
      print('🔄 Refreshing groups screen data on app resume...');

      // Trigger parent to refresh groups data
      final freshGroups = await StorageService.loadGroups();
      widget.onGroupsChanged(freshGroups);

      print('✅ Groups screen data refreshed');
    } catch (e) {
      print('❌ Error refreshing groups screen data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contact Groups',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.square_arrow_down),
            onPressed: _importGroups,
          ),
          IconButton(
            icon: Icon(CupertinoIcons.square_arrow_up),
            onPressed: widget.groups.isEmpty ? null : _exportGroups,
          ),
        ],
      ),
      body: widget.groups.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.person_3,
                      size: 64, color: Color(0xFFD1D1D6)),
                  SizedBox(height: 16),
                  Text('No groups yet',
                      style: TextStyle(fontSize: 18, color: Color(0xFF8E8E93))),
                  SizedBox(height: 8),
                  Text('Tap + to create a group',
                      style: TextStyle(color: Color(0xFF8E8E93))),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: widget.groups.length,
              itemBuilder: (context, index) {
                final group = widget.groups[index];
                return Container(
                  margin: EdgeInsets.only(bottom: 12),
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
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    title: Text(
                      group.name,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${group.contacts.length} contacts',
                      style: TextStyle(color: Color(0xFF8E8E93)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(CupertinoIcons.pencil,
                              color: Color(0xFF007AFF)),
                          onPressed: () => _editGroup(group),
                        ),
                        IconButton(
                          icon: Icon(CupertinoIcons.trash,
                              color: Color(0xFFFF3B30)),
                          onPressed: () => _deleteGroup(group),
                        ),
                      ],
                    ),
                    onTap: () => _viewGroupDetails(group),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGroup,
        backgroundColor: Color(0xFF007AFF),
        heroTag: 'groups_fab',
        child: Icon(CupertinoIcons.add),
      ),
    );
  }

  void _createGroup() async {
    // Try to access contacts directly to test if permission is actually working
    try {
      await ContactsService.getContacts(withThumbnails: false);
      print('✅ Successfully accessed contacts, opening create group screen');

      final result = await Navigator.push(
        context,
        CupertinoPageRoute(builder: (context) => CreateGroupScreen()),
      );
      if (result != null) {
        setState(() {
          widget.groups.add(result);
          widget.onGroupsChanged(widget.groups);
        });
      }
    } catch (e) {
      print('❌ Error accessing contacts: $e');

      // Check if it's a permission issue
      final permissionStatus = await Permission.contacts.status;
      print('🔐 Contacts permission status: $permissionStatus');

      String errorMessage =
          'Unable to access contacts. Please check app permissions.';
      if (permissionStatus.isDenied) {
        errorMessage =
            'Contacts permission is required. Please enable it in Settings.';
      } else if (permissionStatus.isPermanentlyDenied) {
        errorMessage =
            'Contacts permission was permanently denied. Please enable it in Settings.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
        ),
      );
    }
  }

  void _editGroup(ContactGroup group) async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => CreateGroupScreen(group: group)),
    );
    if (result != null) {
      setState(() {
        final index = widget.groups.indexWhere((g) => g.id == group.id);
        widget.groups[index] = result;
        widget.onGroupsChanged(widget.groups);
      });
    }
  }

  void _deleteGroup(ContactGroup group) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete Group'),
        content: Text('Are you sure you want to delete "${group.name}"?'),
        actions: [
          CupertinoDialogAction(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: Text('Delete'),
            onPressed: () {
              setState(() {
                widget.groups.remove(group);
                widget.onGroupsChanged(widget.groups);
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _viewGroupDetails(ContactGroup group) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => GroupDetailsScreen(group: group),
      ),
    );
  }

  void _exportGroups() async {
    List<List<dynamic>> csvData = [
      ['Group Name', 'Contact Name', 'Phone Number'],
    ];

    for (var group in widget.groups) {
      for (var contact in group.contacts) {
        csvData.add([
          group.name,
          contact.displayName ?? '',
          contact.phones?.isNotEmpty == true
              ? contact.phones!.first.value ?? ''
              : '',
        ]);
      }
    }

    String csv = const ListToCsvConverter().convert(csvData);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/contact_groups.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], text: 'Contact Groups Export');
  }

  void _importGroups() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final csvData = const CsvToListConverter().convert(csvString);

      Map<String, List<Contact>> groupsMap = {};

      for (var i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        if (row.length >= 3) {
          final groupName = row[0].toString();
          final contactName = row[1].toString();
          final phoneNumber = row[2].toString();

          if (!groupsMap.containsKey(groupName)) {
            groupsMap[groupName] = [];
          }

          final contact = Contact(
            displayName: contactName,
            phones: [Item(value: phoneNumber)],
          );

          groupsMap[groupName]!.add(contact);
        }
      }

      setState(() {
        for (var entry in groupsMap.entries) {
          widget.groups.add(ContactGroup(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: entry.key,
            contacts: entry.value,
          ));
        }
        widget.onGroupsChanged(widget.groups);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Groups imported successfully')),
      );
    }
  }
}
