import 'package:flutter/material.dart';

import 'expense_draft/expense_draft_form.dart';

void main() {
  runApp(const ZenithExampleApp());
}

class ZenithExampleApp extends StatelessWidget {
  const ZenithExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zenith Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const ExpenseDraftScreen(),
    );
  }
}
