import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'zenith_container.dart';

/// Base abstract class for a 1-to-1 command returning a value of type [R].
///
/// Equivalent to `IRequest<TResponse>` in MediatR.
abstract class ZenithCommand<R> {
  /// Creates a [ZenithCommand].
  const ZenithCommand();
}

/// Base abstract class for a 1-to-Many domain event.
///
/// Equivalent to `INotification` in MediatR.
abstract class ZenithEvent {
  /// Creates a [ZenithEvent].
  const ZenithEvent();
}

/// Function signature for command execution handlers.
typedef ZenithCommandHandler<C extends ZenithCommand<R>, R> =
    FutureOr<R> Function(ZenithRef ref, C command);

/// Function signature for domain event listeners.
typedef ZenithEventHandler<E extends ZenithEvent> =
    FutureOr<void> Function(ZenithRef ref, E event);

/// Abstract pipeline behavior wrapping command execution for cross-cutting concerns
/// (logging, timing, validation, metric capture).
///
/// Equivalent to `IPipelineBehavior<TRequest, TResponse>` in MediatR.
abstract class ZenithPipelineBehavior {
  /// Wraps command execution. Call [next] to proceed to the next behavior or handler.
  Future<R> handle<R>(
    ZenithRef ref,
    ZenithCommand<R> command,
    Future<R> Function() next,
  );
}

/// An in-memory Command/Event Mediator engine for `flutter_zenith`.
///
/// Equivalent to MediatR in .NET. Decouples UI callers from business logic handlers.
class ZenithMediator {
  final ZenithContainer container;
  final Map<Type, Function> _commandHandlers = <Type, Function>{};
  final Map<Type, List<Function>> _eventHandlers = <Type, List<Function>>{};
  final List<ZenithPipelineBehavior> _behaviors = <ZenithPipelineBehavior>[];

  int _callDepth = 0;
  static const int maxCallDepth = 10;

  /// Creates a [ZenithMediator] bound to [container].
  ZenithMediator(this.container);

  /// Registers a 1-to-1 command handler for command type [C].
  void registerCommandHandler<C extends ZenithCommand<R>, R>(
    ZenithCommandHandler<C, R> handler,
  ) {
    _commandHandlers[C] = handler;
  }

  /// Registers a 1-to-Many domain event listener for event type [E].
  void registerEventHandler<E extends ZenithEvent>(
    ZenithEventHandler<E> handler,
  ) {
    _eventHandlers.putIfAbsent(E, () => <Function>[]).add(handler);
  }

  /// Adds a cross-cutting pipeline behavior to this mediator.
  void addBehavior(ZenithPipelineBehavior behavior) {
    _behaviors.add(behavior);
  }

  /// Sends [command] to its registered 1-to-1 command handler.
  ///
  /// Passes through all registered [ZenithPipelineBehavior]s in registration order.
  /// Throws [StateError] if no handler is registered or if re-entrancy depth exceeds 10.
  Future<R> send<R>(ZenithCommand<R> command) async {
    if (_callDepth >= maxCallDepth) {
      throw StateError(
        'ZenithMediator re-entrancy depth limit ($maxCallDepth) exceeded. '
        'Check for recursive command calls (e.g. Command A sending Command A).',
      );
    }

    final handler = _commandHandlers[command.runtimeType];
    if (handler == null) {
      throw StateError(
        'No handler registered for command of type ${command.runtimeType}. '
        'Register a handler via mediator.registerCommandHandler().',
      );
    }

    _callDepth++;

    try {
      final ref = ZenithRef(container);

      Future<R> executePipeline(int index) async {
        if (index < _behaviors.length) {
          final behavior = _behaviors[index];
          return behavior.handle<R>(
            ref,
            command,
            () => executePipeline(index + 1),
          );
        }

        final dynamic untypedHandler = handler;
        final dynamic result = await untypedHandler(ref, command);
        return result as R;
      }

      return await executePipeline(0);
    } finally {
      _callDepth--;
    }
  }

  /// Publishes [event] to all registered 1-to-Many event handlers.
  ///
  /// Handlers are executed with isolated error handling: if one handler throws,
  /// remaining handlers still execute successfully.
  Future<void> publish<E extends ZenithEvent>(E event) async {
    final handlers = _eventHandlers[event.runtimeType];
    if (handlers == null || handlers.isEmpty) {
      return;
    }

    final ref = ZenithRef(container);
    for (final handler in handlers.toList(growable: false)) {
      try {
        final dynamic untypedHandler = handler;
        await untypedHandler(ref, event);
      } catch (error, stackTrace) {
        assert(() {
          debugPrint(
            'ZenithMediator: Event handler for ${event.runtimeType} threw an error: $error\n$stackTrace',
          );
          return true;
        }());
      }
    }
  }
}

/// Extension on [ZenithContainer] and [ZenithRef] giving access to [ZenithMediator].
extension ZenithMediatorContainerX on ZenithContainer {
  /// Gets or creates the [ZenithMediator] for this container.
  ZenithMediator get mediator {
    return getOrCreateNode<ZenithMediator>(
      '_zenith_mediator_key',
      (ref) => ZenithMediator(this),
    ).value;
  }
}

/// Extension on [ZenithRef] for mediator access.
extension ZenithMediatorRefX on ZenithRef {
  /// Gets the [ZenithMediator] for this ref's container.
  ZenithMediator get mediator => container.mediator;
}
