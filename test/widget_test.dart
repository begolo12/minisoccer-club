import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/ui/fmt.dart';

void main() {
  test('format uang & periode', () {
    expect(fmtMoney(100000), 'Rp 100.000');
    expect(fmtMoney(0), 'Rp 0');
    expect(periodLabel('2026-03'), 'Maret 2026');
    expect(periodLabel('bad'), 'bad');
    expect(fmtDate(DateTime(2026, 1, 5)), '5 Jan 2026');
  });
}
