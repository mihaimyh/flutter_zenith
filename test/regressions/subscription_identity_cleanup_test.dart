import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';
import 'package:flutter_zenith/zenith_identity.dart' as identity;

class Listener implements ZenithSubscriber {
  int calls = 0;
  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    calls++;
  }
}

class Account {
  final String id;
  Account(this.id);
}

class AccountDraft extends StatefulWidget {
  final String account;
  const AccountDraft(this.account, {super.key});
  @override
  State<AccountDraft> createState() => AccountDraftState();
}

class AccountDraftState extends State<AccountDraft> {
  late final String draftOwner = widget.account;
  @override
  Widget build(BuildContext context) =>
      Text(draftOwner, textDirection: TextDirection.ltr);
}

void main() {
  test('failed factory must release resources it registered', () async {
    final container = ZenithContainer();
    final stream = StreamController<int>();
    var cancelled = false;
    stream.onCancel = () {
      cancelled = true;
    };
    expect(
      () => container.getOrCreate(const ZenithKey<int>('failed'), (ref) {
        final subscription = stream.stream.listen((_) {});
        ref.onDispose(subscription.cancel);
        throw StateError('configuration failed');
      }),
      throwsStateError,
    );
    await container.disposeAsync();
    await stream.close();
    expect(
      cancelled,
      isTrue,
      reason: 'The failed factory subscription must be cancelled',
    );
  });
  test('old cancellation handle cannot unlink a newer listener', () {
    final node = ZenithNode(0);
    final old = Listener();
    final cancel = node.subscribe(old);
    node.unsubscribe(old);
    final current = Listener();
    node.subscribe(current);
    cancel();
    node.value = 1;
    expect(current.calls, 1, reason: 'New subscriber must remain linked');
    node.dispose();
  });
  test('family arguments with distinct identities must not alias', () {
    final container = ZenithContainer();
    final family = ZenithFamily<String, Account>('profile');
    final alice = Account('alice');
    final bob = Account('bob');
    container.getOrCreate(family(alice), (_) => 'Alice private data');
    final bobNode = container.getOrCreate(
      family(bob),
      (_) => 'Bob private data',
    );
    expect(bobNode.value, 'Bob private data');
    container.dispose();
  });
  testWidgets('account switch discards previous account widget state', (
    tester,
  ) async {
    final coordinator = identity.ZenithIdentityCoordinator();
    await coordinator.signIn('alice');
    await tester.pumpWidget(
      identity.ZenithAuthScope(
        coordinator: coordinator,
        authenticatedBuilder: (_, scope) => AccountDraft(scope.id),
        unauthenticatedBuilder: (_) => const SizedBox(),
      ),
    );
    expect(find.text('alice'), findsOneWidget);
    await coordinator.signIn('bob');
    await tester.pump();
    expect(
      find.text('bob'),
      findsOneWidget,
      reason: 'Alice draft must not survive Bob sign-in',
    );
    await tester.pumpWidget(const SizedBox());
    await coordinator.signOut();
  });
  test('disposeAsync must await stream cancellation', () async {
    final container = ZenithContainer();
    final gate = Completer<void>();
    final stream = StreamController<int>(onCancel: () => gate.future);
    final ref = ZenithRef(container);
    final node = ZenithNode<AsyncValue<int>>(const AsyncData(0));
    ref.watchStream(node, stream.stream);
    var disposed = false;
    final disposal = container.disposeAsync().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    final early = disposed;
    gate.complete();
    await disposal;
    await stream.close();
    node.dispose();
    expect(
      early,
      isFalse,
      reason: 'Async stream cancellation must finish before disposal completes',
    );
  });
  test('auth_header must be redacted', () {
    final sink = MemoryRingBufferSink();
    ZenithLogger(sinks: [sink]).info('Request {auth_header}', {
      'auth_header': 'Bearer private-credential',
    });
    expect(sink.logs.single.properties['auth_header'], '[REDACTED]');
  });
}
