import 'package:eid/eid.dart';
import 'package:test/test.dart';

void main() {
  test('a complete date converts to a DateTime', () {
    final date = PartialDate(1985, 3, 12);
    expect(date.isComplete, isTrue);
    expect(date.toDateTime(), DateTime.utc(1985, 3, 12));
    expect(date.toString(), '1985-03-12');
  });

  test('a partial date prints only what is known', () {
    expect(PartialDate(1950).toString(), '1950');
    expect(PartialDate(1950, 7).toString(), '1950-07');
    expect(PartialDate(1950, 7).toDateTime(), isNull);
  });

  test('refuses a day without a month, or a day the month does not have', () {
    expect(() => PartialDate(1950, null, 3), throwsArgumentError);
    expect(() => PartialDate(2023, 2, 29), throwsRangeError);
    expect(PartialDate(2024, 2, 29).day, 29);
  });

  test('orders an unknown part before a known one', () {
    final dates = [
      PartialDate(1950, 7, 1),
      PartialDate(1950),
      PartialDate(1950, 7)
    ]..sort();
    expect(dates.map((d) => d.toString()), ['1950', '1950-07', '1950-07-01']);
  });

  group('age', () {
    test('counts full years, a year older on the birthday', () {
      final born = PartialDate(1990, 5, 15);
      expect(born.ageOn(DateTime(2026, 5, 14)), 35);
      expect(born.ageOn(DateTime(2026, 5, 15)), 36);
      expect(born.minimumAgeOn(DateTime(2026, 5, 15)), 36);
    });

    test('turns a year older on 1 March when born on 29 February', () {
      final born = PartialDate(2008, 2, 29);
      expect(born.ageOn(DateTime(2026, 2, 28)), 17);
      expect(born.ageOn(DateTime(2026, 3)), 18);
      expect(born.ageOn(DateTime(2028, 2, 29)), 20);
    });

    test('leaves an age the unknown parts make uncertain open', () {
      final born = PartialDate(2008);
      expect(born.ageOn(DateTime(2026, 6, 30)), isNull);
      expect(born.minimumAgeOn(DateTime(2026, 6, 30)), 17);
      expect(born.ageOn(DateTime(2026, 12, 31)), 18);

      final bornInJuly = PartialDate(2008, 7);
      expect(bornInJuly.ageOn(DateTime(2026, 7, 15)), isNull);
      expect(bornInJuly.minimumAgeOn(DateTime(2026, 7, 15)), 17);
      expect(bornInJuly.ageOn(DateTime(2026, 8)), 18);
    });

    test('is never negative', () {
      expect(PartialDate(2030, 1, 1).minimumAgeOn(DateTime(2026)), 0);
    });
  });
}
