import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/message_template.dart';

class CreateTemplateScreen extends StatefulWidget {
  final MessageTemplate? template;

  const CreateTemplateScreen({super.key, this.template});

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
        title: const Text('Delete Template'),
        content:
            Text('Are you sure you want to delete "${widget.template!.name}"?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF3B30))),
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
          child: const Icon(CupertinoIcons.back, color: Color(0xFF007AFF)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          CupertinoButton(
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
            child: const Text('Save',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF007AFF))),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CupertinoTextField(
                      controller: _nameController,
                      placeholder: 'Template Name',
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 200,
                      child: CupertinoTextField(
                        controller: _contentController,
                        placeholder:
                            'Message content...\nUse variables like [First Name] to personalize',
                        padding: const EdgeInsets.all(12),
                        maxLines: null,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Insert Variables:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
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
                  padding: const EdgeInsets.all(16),
                  child: CupertinoButton(
                    color: const Color(0xFFFF3B30),
                    onPressed: _deleteTemplate,
                    child: const Text('Delete Template',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariableChip(String variable) {
    return ActionChip(
      label: Text(variable),
      backgroundColor: const Color(0xFF007AFF).withOpacity(0.1),
      onPressed: () => _insertVariable(variable),
    );
  }
}
