import 'package:flutter_test/flutter_test.dart';
import 'package:rowmate/core/models/workout_session.dart';

DataPoint _p(int hr) => DataPoint(sessionId: 1, elapsedSeconds: 0, heartRate: hr);

void main() {
  test('avgHeartRate y maxHeartRate ignoran los ceros', () {
    final s = SessionStats.compute([_p(0), _p(120), _p(150), _p(0), _p(141)]);
    expect(s.avgHeartRate, 137); // (120 + 150 + 141) / 3
    expect(s.maxHeartRate, 150);
    expect(s.hasHeartRate, isTrue);
  });

  test('sin pulso quedan en 0', () {
    final s = SessionStats.compute([_p(0), _p(0)]);
    expect(s.avgHeartRate, 0);
    expect(s.maxHeartRate, 0);
    expect(s.hasHeartRate, isFalse);
  });

  test('sin puntos quedan en 0', () {
    expect(SessionStats.compute(const []).hasHeartRate, isFalse);
  });
}
