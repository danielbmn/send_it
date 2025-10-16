import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/message_template.dart';

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

  void _deleteTemplate() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('Delete Template'),
        content:
            Text('Are you sure you want to delete "${widget.template!.name}"?'),
        actions: [
          CupertinoDialogAction(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: Text('Delete', style: TextStyle(color: Color(0xFFFF3B30))),
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, 'DELETE'); // Return delete signal
            },
          ),
        ],
      ),
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
          child: Icon(CupertinoIcons.back, color: Color(0xFF007AFF)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
            child: Text('Save',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF007AFF))),
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
                // Note: These variables must match Helpers.templateVariables
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
          if (widget.template != null)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              child: CupertinoButton(
                color: Color(0xFFFF3B30),
                child: Text('Delete Template',
                    style: TextStyle(color: Colors.white)),
                onPressed: _deleteTemplate,
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
