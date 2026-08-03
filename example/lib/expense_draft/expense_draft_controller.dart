import 'dart:async';

import 'package:flutter_zenith/flutter_zenith.dart';

class ExpenseDraftController {
  static const _titleKey = 'expense.title';
  static const _amountKey = 'expense.amount';
  static const _categoryKey = 'expense.category';
  static const _validKey = 'expense.isValid';
  static const _submitKey = 'expense.submit';
  static const _lifecycleKey = 'expense.lifecycle';

  final ZenithContainer container;
  late final ZenithRef _ref;

  late final ZenithNode<String> titleNode;
  late final ZenithNode<String> amountNode;
  late final ZenithNode<String> categoryNode;
  late final ZenithNode<bool> isValidNode;
  late final ZenithNode<AsyncValue<bool>> submitResultNode;

  ExpenseDraftController(this.container) {
    container.getOrCreateNode<bool>(_lifecycleKey, (ref) {
      _ref = ref;
      return true;
    });

    titleNode = container.getOrCreateNode<String>(_titleKey, (_) => '');
    amountNode = container.getOrCreateNode<String>(_amountKey, (_) => '');
    categoryNode = container.getOrCreateNode<String>(_categoryKey, (_) => 'Food');
    isValidNode = container.getOrCreateNode<bool>(_validKey, (_) => false);
    submitResultNode = container.getOrCreateNode<AsyncValue<bool>>(
      _submitKey,
      (_) => const AsyncData<bool>(false),
    );

    _ref.onDispose(() {
      if (!submitResultNode.isDisposed) {
        submitResultNode.set(const AsyncData<bool>(false));
      }
    });
  }

  void updateTitle(String value) {
    titleNode.set(value);
    _recomputeIsValid();
  }

  void updateAmount(String value) {
    amountNode.set(value);
    _recomputeIsValid();
  }

  void updateCategory(String value) {
    categoryNode.set(value);
  }

  void _recomputeIsValid() {
    final parsedAmount = double.tryParse(amountNode.value);
    final next = titleNode.value.trim().isNotEmpty && parsedAmount != null && parsedAmount > 0;

    isValidNode.set(next);
  }

  Future<void> submit() async {
    if (!isValidNode.value) {
      return;
    }

    final previous = submitResultNode.value.valueOrNull;
    submitResultNode.set(AsyncLoading<bool>(previous));

    try {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!_ref.isMounted) {
        return;
      }
      submitResultNode.set(const AsyncData<bool>(true));
    } catch (error, stackTrace) {
      if (!_ref.isMounted) {
        return;
      }
      submitResultNode.set(AsyncError<bool>(error, stackTrace));
    }
  }
}
