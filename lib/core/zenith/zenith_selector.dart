import 'package:flutter/widgets.dart';

import 'zenith_node.dart';

/// A widget that rebuilds only when a selected portion of a [ZenithNode]'s
/// value changes.
///
/// Unlike [ZenithBuilder] which rebuilds when *any* read node changes,
/// [ZenithSelector] extracts a derived value via [selector] and only rebuilds
/// when that derived value is different from the previous one (compared with
/// `==`).
///
/// This is essential for performance in list-heavy UIs where a single node
/// holds a large collection but individual widgets only care about one
/// element:
///
/// ```dart
/// ZenithSelector<List<Item>, String>(
///   node: itemsNode,
///   selector: (items) => items[index].name,
///   builder: (context, name) => Text(name),
/// )
/// ```
class ZenithSelector<T, R> extends StatefulWidget {
  /// The source node to observe.
  final ZenithNode<T> node;

  /// Extracts the derived value from the node's current value.
  ///
  /// The widget only rebuilds when the result of this function changes.
  final R Function(T value) selector;

  /// Builds the widget subtree using the selected value.
  final Widget Function(BuildContext context, R selected) builder;

  /// Creates a [ZenithSelector].
  const ZenithSelector({
    super.key,
    required this.node,
    required this.selector,
    required this.builder,
  });

  @override
  State<ZenithSelector<T, R>> createState() => _ZenithSelectorState<T, R>();
}

class _ZenithSelectorState<T, R> extends State<ZenithSelector<T, R>>
    implements ZenithSubscriber {
  late R _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selector(widget.node.value);
    widget.node.subscribe(this);
  }

  @override
  void didUpdateWidget(covariant ZenithSelector<T, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node)) {
      oldWidget.node.unsubscribe(this);
      widget.node.subscribe(this);
      _selectedValue = widget.selector(widget.node.value);
    }
  }

  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    if (!mounted) return;
    final newSelected = widget.selector(widget.node.value);
    if (newSelected != _selectedValue) {
      setState(() {
        _selectedValue = newSelected;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _selectedValue);
  }

  @override
  void dispose() {
    widget.node.unsubscribe(this);
    super.dispose();
  }
}
