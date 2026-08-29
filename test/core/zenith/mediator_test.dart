import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

// Commands
class CalculateTotalCommand extends ZenithCommand<int> {
  final int a;
  final int b;
  CalculateTotalCommand(this.a, this.b);
}

class RecursiveCommand extends ZenithCommand<void> {}

// Events
class OrderPlacedEvent extends ZenithEvent {
  final String orderId;
  OrderPlacedEvent(this.orderId);
}

void main() {
  group('ZenithMediator Commands', () {
    test('send executes registered command handler and returns result', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      mediator.registerCommandHandler<CalculateTotalCommand, int>(
        (ref, cmd) => cmd.a + cmd.b,
      );

      final result = await mediator.send(CalculateTotalCommand(15, 25));
      expect(result, 40);
    });

    test('send throws StateError when no handler is registered', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      expect(
        () => mediator.send(CalculateTotalCommand(1, 2)),
        throwsStateError,
      );
    });

    test('detects re-entrancy depth limit and throws StateError on infinite loops', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      mediator.registerCommandHandler<RecursiveCommand, void>(
        (ref, cmd) async {
          await mediator.send(RecursiveCommand());
        },
      );

      expect(
        () => mediator.send(RecursiveCommand()),
        throwsStateError,
      );
    });
  });

  group('ZenithMediator Events', () {
    test('publish broadcasts domain event to all registered handlers', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      final eventsReceivedA = <String>[];
      final eventsReceivedB = <String>[];

      mediator.registerEventHandler<OrderPlacedEvent>((ref, event) {
        eventsReceivedA.add(event.orderId);
      });

      mediator.registerEventHandler<OrderPlacedEvent>((ref, event) {
        eventsReceivedB.add(event.orderId);
      });

      await mediator.publish(OrderPlacedEvent('order_999'));

      expect(eventsReceivedA, equals(['order_999']));
      expect(eventsReceivedB, equals(['order_999']));
    });

    test('isolated error handling: failing handler does not stop remaining handlers', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      final successReceived = <String>[];

      mediator.registerEventHandler<OrderPlacedEvent>((ref, event) {
        throw Exception('Failing handler');
      });

      mediator.registerEventHandler<OrderPlacedEvent>((ref, event) {
        successReceived.add(event.orderId);
      });

      await mediator.publish(OrderPlacedEvent('order_777'));

      // Handler 2 still received event despite Handler 1 failing
      expect(successReceived, equals(['order_777']));
    });
  });

  group('ZenithMediator Pipeline Behaviors', () {
    test('pipeline behaviors wrap command execution in registration order', () async {
      final container = ZenithContainer();
      final mediator = container.mediator;

      final executionTrace = <String>[];

      mediator.addBehavior(_TracingBehavior('Behavior 1', executionTrace));
      mediator.addBehavior(_TracingBehavior('Behavior 2', executionTrace));

      mediator.registerCommandHandler<CalculateTotalCommand, int>((ref, cmd) {
        executionTrace.add('handler');
        return cmd.a + cmd.b;
      });

      final result = await mediator.send(CalculateTotalCommand(5, 5));

      expect(result, 10);
      expect(
        executionTrace,
        equals([
          'Behavior 1:before',
          'Behavior 2:before',
          'handler',
          'Behavior 2:after',
          'Behavior 1:after',
        ]),
      );
    });
  });
}

class _TracingBehavior extends ZenithPipelineBehavior {
  final String name;
  final List<String> trace;

  _TracingBehavior(this.name, this.trace);

  @override
  Future<R> handle<R>(
    ZenithRef ref,
    ZenithCommand<R> command,
    Future<R> Function() next,
  ) async {
    trace.add('$name:before');
    final result = await next();
    trace.add('$name:after');
    return result;
  }
}
