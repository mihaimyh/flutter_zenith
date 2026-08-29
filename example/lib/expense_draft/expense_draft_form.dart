import 'package:flutter/material.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

import 'expense_draft_controller.dart';

class ExpenseDraftScreen extends StatefulWidget {
  const ExpenseDraftScreen({super.key});

  @override
  State<ExpenseDraftScreen> createState() => _ExpenseDraftScreenState();
}

class _ExpenseDraftScreenState extends State<ExpenseDraftScreen> {
  late final ZenithContainer _container;
  late final ExpenseDraftController _controller;

  @override
  void initState() {
    super.initState();
    _container = ZenithContainer();
    _controller = ExpenseDraftController(_container);
  }

  @override
  Widget build(BuildContext context) {
    return ZenithScope(
      container: _container,
      child: Scaffold(
        appBar: AppBar(title: const Text('Expense Draft')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ZenithBuilder(
                builder: (context) {
                  final title = _controller.titleNode.value;
                  return TextFormField(
                    key: const Key('title-field'),
                    initialValue: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    onChanged: _controller.updateTitle,
                  );
                },
              ),
              const SizedBox(height: 12),
              ZenithBuilder(
                builder: (context) {
                  final amount = _controller.amountNode.value;
                  return TextFormField(
                    key: const Key('amount-field'),
                    initialValue: amount,
                    decoration: const InputDecoration(labelText: 'Amount'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _controller.updateAmount,
                  );
                },
              ),
              const SizedBox(height: 12),
              ZenithBuilder(
                builder: (context) {
                  final category = _controller.categoryNode.value;
                  return DropdownButtonFormField<String>(
                    key: const Key('category-field'),
                    initialValue: category,
                    items: const [
                      DropdownMenuItem(value: 'Food', child: Text('Food')),
                      DropdownMenuItem(value: 'Travel', child: Text('Travel')),
                      DropdownMenuItem(
                        value: 'Utilities',
                        child: Text('Utilities'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _controller.updateCategory(value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Category'),
                  );
                },
              ),
              const SizedBox(height: 20),
              ZenithBuilder(
                builder: (context) {
                  final isValid = _controller.isValidNode.value;
                  final state = _controller.submitResultNode.value;

                  return ElevatedButton(
                    key: const Key('submit-button'),
                    onPressed: isValid ? _controller.submit : null,
                    child: state.when(
                      data: (ok) => Text(ok ? 'Submitted' : 'Submit Expense'),
                      loading: (_) => const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, _) => const Text('Retry Submit'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
