// test/reconnect_loop_test.dart
import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/bluetooth/reconnect_loop.dart';

void main() {
  group('ReconnectLoop', () {
    test('intenta de inmediato, reintenta cada intervalo y para al tener éxito', () {
      fakeAsync((async) {
        var calls = 0;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 3),
          attempt: () async => ++calls >= 3,
        );
        loop.start();
        async.flushMicrotasks();
        expect(calls, 1);
        expect(loop.isRunning, isTrue);

        async.elapse(const Duration(seconds: 3));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 3));
        expect(calls, 3);
        expect(loop.isRunning, isFalse);

        async.elapse(const Duration(seconds: 30));
        expect(calls, 3, reason: 'no sigue intentando tras el éxito');
      });
    });

    test('se rinde tras maxAttempts y avisa', () {
      fakeAsync((async) {
        var calls = 0;
        var gaveUp = false;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 10),
          maxAttempts: 3,
          attempt: () async {
            calls++;
            return false;
          },
          onGiveUp: () => gaveUp = true,
        );
        loop.start();
        async.elapse(const Duration(seconds: 25));
        expect(calls, 3);
        expect(gaveUp, isTrue);
        expect(loop.isRunning, isFalse);
        async.elapse(const Duration(seconds: 60));
        expect(calls, 3);
      });
    });

    test('cancel frena los reintentos y una excepción cuenta como fallo', () {
      fakeAsync((async) {
        var calls = 0;
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 1),
          attempt: () async {
            calls++;
            throw StateError('sin BT');
          },
        );
        loop.start();
        async.elapse(const Duration(seconds: 2));
        expect(calls, 3);
        loop.cancel();
        expect(loop.isRunning, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(calls, 3);
      });
    });

    test('start() durante un intento en vuelo descarta ese resultado y arranca de cero', () {
      fakeAsync((async) {
        final completers = <Completer<bool>>[];
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 3),
          attempt: () {
            final c = Completer<bool>();
            completers.add(c);
            return c.future;
          },
        );
        loop.start();
        expect(completers, hasLength(1));

        loop.start(); // reinicio mientras el primer intento sigue en vuelo
        expect(completers, hasLength(2), reason: 'la nueva corrida intenta de inmediato');
        expect(loop.attempts, 1);

        completers[0].complete(true); // éxito tardío de la corrida vieja
        async.flushMicrotasks();
        expect(loop.isRunning, isTrue, reason: 'el éxito viejo no termina la corrida nueva');

        completers[1].complete(false);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(completers, hasLength(3));
        expect(loop.attempts, 2);
      });
    });

    test('cancel() durante un intento en vuelo no programa otro intento', () {
      fakeAsync((async) {
        final completers = <Completer<bool>>[];
        final loop = ReconnectLoop(
          interval: const Duration(seconds: 1),
          attempt: () {
            final c = Completer<bool>();
            completers.add(c);
            return c.future;
          },
        );
        loop.start();
        loop.cancel();
        completers.single.complete(false);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(completers, hasLength(1));
        expect(loop.isRunning, isFalse);
      });
    });

    test('start() desde onGiveUp arranca una corrida nueva', () {
      fakeAsync((async) {
        var calls = 0;
        var giveUps = 0;
        late final ReconnectLoop loop;
        loop = ReconnectLoop(
          interval: const Duration(seconds: 1),
          maxAttempts: 2,
          attempt: () async {
            calls++;
            return false;
          },
          onGiveUp: () {
            if (++giveUps == 1) loop.start();
          },
        );
        loop.start();
        async.elapse(const Duration(seconds: 1)); // 2 fallos → give up → start → intento 3 inmediato
        expect(giveUps, 1);
        expect(calls, 3);
        expect(loop.isRunning, isTrue);

        async.elapse(const Duration(seconds: 1));
        expect(calls, 4);
        expect(giveUps, 2);
        expect(loop.isRunning, isFalse);
      });
    });
  });

  group('StaleWatchdog', () {
    test('dispara tras el timeout sin touch, y touch lo rearma', () {
      fakeAsync((async) {
        var stale = 0;
        final w = StaleWatchdog(timeout: const Duration(seconds: 10), onStale: () => stale++);
        w.touch();
        async.elapse(const Duration(seconds: 9));
        w.touch();
        async.elapse(const Duration(seconds: 9));
        expect(stale, 0);
        async.elapse(const Duration(seconds: 1));
        expect(stale, 1);
        async.elapse(const Duration(seconds: 30));
        expect(stale, 1, reason: 'dispara una sola vez por touch');
        w.touch();
        w.stop();
        async.elapse(const Duration(seconds: 30));
        expect(stale, 1);
      });
    });
  });
}
