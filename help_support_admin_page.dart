import 'package:flutter/material.dart';

import '../../../widgets/reusable_widgets/support_chat.dart';

class HelpSupportAdminPage extends StatelessWidget {
  const HelpSupportAdminPage({required this.active, super.key});
  final bool active;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(48, 12, 16, 16),
          child: Text(
            'Help and Support',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SupportChat(admin: true, active: active),
          ),
        ),
      ],
    ),
  );
}
