import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
// import 'dart:convert';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Group Messenger',
      theme: ThemeData(
        primaryColor: Color(0xFF007AFF),
        scaffoldBackgroundColor: Color(0xFFF2F2F7),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFFF9F9F9),
          foregroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      home: HomeScreen(),
    );
  }
}

class ContactGroup {
  String id;
  String name;
  List<Contact> contacts;

  ContactGroup({required this.id, required this.name, required this.contacts});
}

class MessageTemplate {
  String id;
  String name;
  String content;

  MessageTemplate(
      {required this.id, required this.name, required this.content});
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  List<ContactGroup> _groups = [];
  List<MessageTemplate> _templates = [];

  @override
  void initState() {
    super.initState();
    // Don't check permissions on startup at all
    // Only check when user actually tries to use contacts
    print('🚀 App started - no permission check on startup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            GroupsScreen(
                groups: _groups,
                onGroupsChanged: (groups) {
                  setState(() => _groups = groups);
                }),
            TemplatesScreen(
                templates: _templates,
                groups: _groups,
                onTemplatesChanged: (templates) {
                  setState(() => _templates = templates);
                }),
            SendScreen(groups: _groups, templates: _templates),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: Color(0xFF007AFF),
          unselectedItemColor: Color(0xFF8E8E93),
          items: [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person_3_fill),
              label: 'Groups',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.doc_text_fill),
              label: 'Templates',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.paperplane_fill),
              label: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}

class GroupsScreen extends StatefulWidget {
  final List<ContactGroup> groups;
  final Function(List<ContactGroup>) onGroupsChanged;

  GroupsScreen({required this.groups, required this.onGroupsChanged});

  @override
  _GroupsScreenState createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
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
    // Try to get contacts directly - this will trigger permission request
    print('🔐 Attempting to access contacts directly...');
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contacts permission is required to create groups'),
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

class CreateGroupScreen extends StatefulWidget {
  final ContactGroup? group;

  CreateGroupScreen({this.group});

  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  List<Contact> _selectedContacts = [];
  List<Contact> _allContacts = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.group != null) {
      _nameController.text = widget.group!.name;
      _selectedContacts = List.from(widget.group!.contacts);
    }
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      print('🔍 Loading contacts...');

      final contacts = await ContactsService.getContacts(withThumbnails: false);
      final contactsList = contacts.where((contact) {
        return contact.displayName != null &&
            contact.displayName!.isNotEmpty &&
            contact.phones != null &&
            contact.phones!.isNotEmpty;
      }).toList();

      setState(() {
        _allContacts = contactsList;
        _loading = false;
        if (_allContacts.isEmpty) {
          _errorMessage = 'No contacts found with phone numbers';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Error loading contacts: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group == null ? 'Create Group' : 'Edit Group'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
            child: Text('Save',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: (_nameController.text.isNotEmpty &&
                          _selectedContacts.isNotEmpty)
                      ? Color(0xFF007AFF)
                      : Color(0xFF8E8E93),
                )),
            onPressed: (_nameController.text.isNotEmpty &&
                    _selectedContacts.isNotEmpty)
                ? () {
                    final group = ContactGroup(
                      id: widget.group?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      name: _nameController.text,
                      contacts: _selectedContacts,
                    );
                    Navigator.pop(context, group);
                  }
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(16),
            child: CupertinoTextField(
              controller: _nameController,
              placeholder: 'Group Name',
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '${_selectedContacts.length} contacts selected',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CupertinoActivityIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CupertinoIcons.exclamationmark_circle,
                                size: 64, color: Color(0xFFFF3B30)),
                            SizedBox(height: 16),
                            Text(_errorMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF8E8E93))),
                            if (_errorMessage.contains('permission'))
                              Padding(
                                padding: EdgeInsets.only(top: 16),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _allContacts.length,
                        itemBuilder: (context, index) {
                          final contact = _allContacts[index];
                          final isSelected = _selectedContacts
                              .any((c) => c.identifier == contact.identifier);

                          return ListTile(
                            title: Text(contact.displayName ?? 'Unknown'),
                            subtitle: Text(
                              contact.phones?.isNotEmpty == true
                                  ? contact.phones!.first.value ?? ''
                                  : 'No phone number',
                              style: TextStyle(color: Color(0xFF8E8E93)),
                            ),
                            trailing: isSelected
                                ? Icon(CupertinoIcons.checkmark_circle_fill,
                                    color: Color(0xFF007AFF))
                                : Icon(CupertinoIcons.circle,
                                    color: Color(0xFFD1D1D6)),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedContacts.removeWhere((c) =>
                                      c.identifier == contact.identifier);
                                } else {
                                  _selectedContacts.add(contact);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

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

class TemplatesScreen extends StatefulWidget {
  final List<MessageTemplate> templates;
  final List<ContactGroup> groups;
  final Function(List<MessageTemplate>) onTemplatesChanged;

  TemplatesScreen(
      {required this.templates,
      required this.groups,
      required this.onTemplatesChanged});

  @override
  _TemplatesScreenState createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Message Templates',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: widget.templates.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.doc_text,
                      size: 64, color: Color(0xFFD1D1D6)),
                  SizedBox(height: 16),
                  Text('No templates yet',
                      style: TextStyle(fontSize: 18, color: Color(0xFF8E8E93))),
                  SizedBox(height: 8),
                  Text('Tap + to create a template',
                      style: TextStyle(color: Color(0xFF8E8E93))),
                ],
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: widget.templates.length,
              itemBuilder: (context, index) {
                final template = widget.templates[index];
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
                      template.name,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      template.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFF8E8E93)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(CupertinoIcons.pencil,
                              color: Color(0xFF007AFF)),
                          onPressed: () => _editTemplate(template),
                        ),
                        IconButton(
                          icon: Icon(CupertinoIcons.trash,
                              color: Color(0xFFFF3B30)),
                          onPressed: () => _deleteTemplate(template),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTemplate,
        backgroundColor: Color(0xFF007AFF),
        heroTag: 'templates_fab',
        child: Icon(CupertinoIcons.add),
      ),
    );
  }

  void _createTemplate() async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => CreateTemplateScreen()),
    );
    if (result != null) {
      setState(() {
        widget.templates.add(result);
        widget.onTemplatesChanged(widget.templates);
      });
    }
  }

  void _editTemplate(MessageTemplate template) async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => CreateTemplateScreen(template: template),
      ),
    );
    if (result != null) {
      setState(() {
        final index = widget.templates.indexWhere((t) => t.id == template.id);
        widget.templates[index] = result;
        widget.onTemplatesChanged(widget.templates);
      });
    }
  }

  void _deleteTemplate(MessageTemplate template) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
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
                widget.templates.remove(template);
                widget.onTemplatesChanged(widget.templates);
              });
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class CreateTemplateScreen extends StatefulWidget {
  final MessageTemplate? template;

  CreateTemplateScreen({this.template});

  @override
  _CreateTemplateScreenState createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.template != null) {
      _nameController.text = widget.template!.name;
      _contentController.text = widget.template!.content;
    }
  }

  void _insertVariable(String variable) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      variable,
    );
    _contentController.text = newText;
    _contentController.selection = TextSelection.fromPosition(
      TextPosition(offset: selection.start + variable.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.template == null ? 'Create Template' : 'Edit Template'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Text('Cancel'),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
            child: Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed:
                _nameController.text.isEmpty || _contentController.text.isEmpty
                    ? null
                    : () {
                        final template = MessageTemplate(
                          id: widget.template?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: _nameController.text,
                          content: _contentController.text,
                        );
                        Navigator.pop(context, template);
                      },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                CupertinoTextField(
                  controller: _nameController,
                  placeholder: 'Template Name',
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 16),
                Container(
                  height: 200,
                  child: CupertinoTextField(
                    controller: _contentController,
                    placeholder:
                        'Message content...\nUse variables like [First Name] to personalize',
                    padding: EdgeInsets.all(12),
                    maxLines: null,
                    decoration: BoxDecoration(
                      color: Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insert Variables:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildVariableChip('[First Name]'),
                    _buildVariableChip('[Last Name]'),
                    _buildVariableChip('[Full Name]'),
                    _buildVariableChip('[Phone]'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableChip(String variable) {
    return ActionChip(
      label: Text(variable),
      backgroundColor: Color(0xFF007AFF).withOpacity(0.1),
      onPressed: () => _insertVariable(variable),
    );
  }
}

class SendScreen extends StatefulWidget {
  final List<ContactGroup> groups;
  final List<MessageTemplate> templates;

  SendScreen({required this.groups, required this.templates});

  @override
  _SendScreenState createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  ContactGroup? _selectedGroup;
  MessageTemplate? _selectedTemplate;
  bool _sending = false;

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
        print('Failed to send to ${contact.displayName}: $e');
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

    message = message.replaceAll('[First Name]', firstName);
    message = message.replaceAll('[Last Name]', lastName);
    message = message.replaceAll('[Full Name]', fullName);
    message = message.replaceAll(
        '[Phone]',
        contact.phones?.isNotEmpty == true
            ? contact.phones!.first.value ?? ''
            : '');

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
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: {'body': message},
    );

    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    } else {
      throw Exception('Could not launch SMS app');
    }
  }
}
