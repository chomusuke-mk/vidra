import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vidra/features/system/domain/system_state.dart';

/// Testable SystemState processor replicating the message handling logic of SystemController
class TestableSystemStateProcessor {
  SystemState _state = SystemState.initializing;
  SystemState get state => _state;

  int notificationCount = 0;
  bool fatalErrorDialogTriggered = false;
  Completer<void>? pauseCompleter;
  Completer<void> portReadyCompleter = Completer<void>();

  void _setState(SystemState newState) {
    if (_state != newState) {
      _state = newState;
      notificationCount++;
      if (_state == SystemState.fatalError) {
        fatalErrorDialogTriggered = true;
      }
    }
  }

  void handleMessage(dynamic message) {
    if (message is Map<String, dynamic>) {
      if (message['event'] == 'port') {
        if (!portReadyCompleter.isCompleted) {
          portReadyCompleter.complete();
        }
      } else if (message['event'] == 'state') {
        final String stateStr = message['value'];
        switch (stateStr) {
          case 'initializing':
          case 'unpacking':
            _setState(SystemState.initializing);
            break;
          case 'missingPermissions':
            _setState(SystemState.missingPermissions);
            break;
          case 'missingResources':
            _setState(SystemState.missingResources);
            break;
          case 'startingBackend':
            _setState(SystemState.startingBackend);
            break;
          case 'retrying':
            _setState(SystemState.retrying);
            break;
          case 'fatalError':
            _setState(SystemState.fatalError);
            break;
          case 'ready':
            _setState(SystemState.ready);
            break;
        }
      } else if (message['event'] == 'paused_ack') {
        pauseCompleter?.complete();
      }
    }
  }
}

void main() {
  group('SystemController State Handling & Transitions', () {
    test('transitions correctly across all isolate state events', () {
      final processor = TestableSystemStateProcessor();

      expect(processor.state, equals(SystemState.initializing));
      expect(processor.notificationCount, equals(0));

      // 1. missingPermissions
      processor.handleMessage({'event': 'state', 'value': 'missingPermissions'});
      expect(processor.state, equals(SystemState.missingPermissions));
      expect(processor.notificationCount, equals(1));

      // 2. missingResources
      processor.handleMessage({'event': 'state', 'value': 'missingResources'});
      expect(processor.state, equals(SystemState.missingResources));
      expect(processor.notificationCount, equals(2));

      // 3. unpacking -> maps to SystemState.initializing
      processor.handleMessage({'event': 'state', 'value': 'unpacking'});
      expect(processor.state, equals(SystemState.initializing));
      expect(processor.notificationCount, equals(3));

      // 4. startingBackend
      processor.handleMessage({'event': 'state', 'value': 'startingBackend'});
      expect(processor.state, equals(SystemState.startingBackend));
      expect(processor.notificationCount, equals(4));

      // 5. ready
      processor.handleMessage({'event': 'state', 'value': 'ready'});
      expect(processor.state, equals(SystemState.ready));
      expect(processor.notificationCount, equals(5));

      // 6. retrying
      processor.handleMessage({'event': 'state', 'value': 'retrying'});
      expect(processor.state, equals(SystemState.retrying));
      expect(processor.notificationCount, equals(6));

      // 7. fatalError -> triggers fatal error dialog
      expect(processor.fatalErrorDialogTriggered, isFalse);
      processor.handleMessage({'event': 'state', 'value': 'fatalError'});
      expect(processor.state, equals(SystemState.fatalError));
      expect(processor.notificationCount, equals(7));
      expect(processor.fatalErrorDialogTriggered, isTrue);
    });

    test('deduplicates consecutive identical state notifications', () {
      final processor = TestableSystemStateProcessor();

      // Setting ready
      processor.handleMessage({'event': 'state', 'value': 'ready'});
      expect(processor.state, equals(SystemState.ready));
      expect(processor.notificationCount, equals(1));

      // Repeated ready notifications should not notify listeners again
      processor.handleMessage({'event': 'state', 'value': 'ready'});
      processor.handleMessage({'event': 'state', 'value': 'ready'});
      expect(processor.notificationCount, equals(1));
    });

    test('handles port event and completes portReadyCompleter', () async {
      final processor = TestableSystemStateProcessor();
      expect(processor.portReadyCompleter.isCompleted, isFalse);

      processor.handleMessage({'event': 'port', 'value': null});
      expect(processor.portReadyCompleter.isCompleted, isTrue);
    });

    test('handles paused_ack event and completes pauseCompleter', () async {
      final processor = TestableSystemStateProcessor();
      processor.pauseCompleter = Completer<void>();

      expect(processor.pauseCompleter!.isCompleted, isFalse);
      processor.handleMessage({'event': 'paused_ack'});
      expect(processor.pauseCompleter!.isCompleted, isTrue);
    });
  });
}
