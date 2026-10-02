import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/features/workout/scene/environment.dart';

String _key(ShoreProp p) => '${p.kind}:${p.x}:${p.z}:${p.seed}';

void main() {
  for (final id in EnvironmentId.values) {
    final env = Environment.of(id);

    test('$id: propsForSegment es determinista', () {
      final a = env.propsForSegment(7).map(_key).toList();
      final b = env.propsForSegment(7).map(_key).toList();
      expect(a, b);
      expect(a, isNot(env.propsForSegment(8).map(_key).toList()));
    });

    test('$id: cada segmento tiene objetos y quedan dentro del segmento', () {
      for (var k = 0; k < 30; k++) {
        final props = env.propsForSegment(k);
        expect(props, isNotEmpty, reason: 'segmento $k vacío');
        for (final p in props) {
          expect(p.z, inInclusiveRange(k * Environment.segmentLength, (k + 1) * Environment.segmentLength));
          if (p.kind != PropKind.bridge && p.kind != PropKind.laneBuoy) {
            expect(p.x.abs(), greaterThanOrEqualTo(Environment.bankX), reason: '${p.kind} en el agua');
          }
        }
      }
    });

    test('$id: visibleProps ordena de lejos a cerca y respeta el máximo', () {
      final props = env.visibleProps(1234);
      expect(props.length, lessThanOrEqualTo(env.maxVisibleProps));
      for (var i = 1; i < props.length; i++) {
        expect(props[i].z, lessThanOrEqualTo(props[i - 1].z));
      }
      for (final p in props) {
        expect(p.z, inInclusiveRange(1235, 1234 + Environment.visibleRange));
      }
    });
  }

  test('el canal de regata tiene boyas cada 10 m', () {
    final buoys = Environment.of(EnvironmentId.regatta)
        .propsForSegment(3)
        .where((p) => p.kind == PropKind.laneBuoy)
        .map((p) => p.z)
        .toSet()
        .toList()
      ..sort();
    expect(buoys.length, 5);
    expect(buoys[1] - buoys[0], 10);
  });

  test('en la regata los hitos lejanos se ven aunque haya muchas boyas', () {
    final props = Environment.of(EnvironmentId.regatta).visibleProps(0);
    const landmarks = {PropKind.grandstand, PropKind.finishTower, PropKind.distanceMarker};
    expect(props.any((p) => landmarks.contains(p.kind) && p.z > 150), isTrue);
  });

  test('el río urbano tiene un puente cada 800 m', () {
    final env = Environment.of(EnvironmentId.river);
    final withBridge = List.generate(32, (k) => k)
        .where((k) => env.propsForSegment(k).any((p) => p.kind == PropKind.bridge))
        .toList();
    expect(withBridge, [5, 21]);
  });
}
