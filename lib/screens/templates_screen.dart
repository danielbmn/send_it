import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/message_template.dart';
import '../models/contact_group.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import 'create_template_screen.dart';

class TemplatesScreen extends StatefulWidget {
  final List<MessageTemplate> templates;
  final List<ContactGroup> groups;
  final Function(List<MessageTemplate>) onTemplatesChanged;

  const TemplatesScreen(
      {super.key,
      required this.templates,
      required this.groups,
      required this.onTemplatesChanged});

  @override
  _TemplatesScreenState createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen>
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
      Logger.info('Refreshing templates screen data on app resume...');

      // Trigger parent to refresh templates data
      final freshTemplates = await StorageService.loadTemplates();
      widget.onTemplatesChanged(freshTemplates);

      Logger.success('Templates screen data refreshed');
    } catch (e) {
      Logger.error('Error refreshing templates screen data', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Templates',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: widget.templates.isEmpty
          ? const Center(
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
              padding: const EdgeInsets.all(16),
              itemCount: widget.templates.length,
              itemBuilder: (context, index) {
                final template = widget.templates[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(
                      template.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      template.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF8E8E93)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.pencil,
                              color: Color(0xFF007AFF)),
                          onPressed: () => _editTemplate(template),
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.trash,
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
        backgroundColor: const Color(0xFF007AFF),
        heroTag: 'templates_fab',
        child: const Icon(CupertinoIcons.add),
      ),
    );
  }

  void _createTemplate() async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => const CreateTemplateScreen()),
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
        title: const Text('Delete Template'),
        content: Text('Are you sure you want to delete "${template.name}"?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
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
