import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/contact_group.dart';
import '../models/message_template.dart';
import '../services/storage_service.dart';
import 'groups_screen.dart';
import 'templates_screen.dart';
import 'send_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  List<ContactGroup> _groups = [];
  List<MessageTemplate> _templates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    print('🚀 App started - loading saved data');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, validate groups in case contacts were deleted
      _validateGroupsOnResume();
    }
  }

  Future<void> _validateGroupsOnResume() async {
    try {
      final validatedGroups =
          await StorageService.validateAndCleanGroups(_groups);
      if (validatedGroups.length != _groups.length ||
          validatedGroups.any((group) =>
              group.contacts.length !=
              _groups.firstWhere((g) => g.id == group.id).contacts.length)) {
        setState(() {
          _groups = validatedGroups;
        });
        print('🔄 Groups updated after app resume');
      }
    } catch (e) {
      print('❌ Error validating groups on resume: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      final groups = await StorageService.loadGroups();
      final templates = await StorageService.loadTemplates();

      // Validate and clean up groups to remove deleted contacts
      final validatedGroups =
          await StorageService.validateAndCleanGroups(groups);

      setState(() {
        _groups = validatedGroups;
        _templates = templates;
        _isLoading = false;
      });

      print('✅ Data loaded and validated successfully');
    } catch (e) {
      print('❌ Error loading data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGroups() async {
    await StorageService.saveGroups(_groups);
  }

  Future<void> _saveTemplates() async {
    await StorageService.saveTemplates(_templates);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CupertinoActivityIndicator(radius: 20),
              SizedBox(height: 16),
              Text('Loading your data...',
                  style: TextStyle(color: Color(0xFF8E8E93))),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            GroupsScreen(
                groups: _groups,
                onGroupsChanged: (groups) {
                  setState(() => _groups = groups);
                  _saveGroups();
                }),
            TemplatesScreen(
                templates: _templates,
                groups: _groups,
                onTemplatesChanged: (templates) {
                  setState(() => _templates = templates);
                  _saveTemplates();
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

