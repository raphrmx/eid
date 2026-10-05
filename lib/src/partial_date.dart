/// A date whose day, or day and month, may be unknown, as on some birth
/// dates.
final class PartialDate implements Comparable<PartialDate> {
  /// The date [year], [month], [day]. A [day] requires a [month].
  PartialDate(this.year, [this.month, this.day]) {
    if (month != null) RangeError.checkValueInInterval(month!, 1, 12, 'month');
    if (day != null) {
      if (month == null) {
        throw ArgumentError.value(day, 'day', 'A day needs a month');
      }
      RangeError.checkValueInInterval(day!, 1, _daysIn(year, month!), 'day');
    }
  }

  /// The year.
  final int year;

  /// The month, 1 for January, or null when unknown.
  final int? month;

  /// The day of the month, or null when unknown.
  final int? day;

  /// Whether the day and month are both known.
  bool get isComplete => day != null;

  /// The date at midnight UTC, or null unless it [isComplete].
  DateTime? toDateTime() =>
      isComplete ? DateTime.utc(year, month!, day!) : null;

  /// The age in full years on [date], or null when the unknown parts make it
  /// ambiguous. Only the calendar day of [date] counts.
  int? ageOn(DateTime date) {
    final youngest = minimumAgeOn(date);
    return youngest == _ageOn(date, month ?? 1, day ?? 1) ? youngest : null;
  }

  /// The lowest possible age in full years on [date], never negative.
  ///
  /// Use it to check a minimum age, such as 18.
  int minimumAgeOn(DateTime date) {
    final lastMonth = month ?? 12;
    return _ageOn(date, lastMonth, day ?? _daysIn(year, lastMonth));
  }

  int _ageOn(DateTime date, int month, int day) {
    final age = date.year -
        year -
        (date.month < month || date.month == month && date.day < day ? 1 : 0);
    return age < 0 ? 0 : age;
  }

  /// Orders by year, month, then day; an unknown part comes first.
  @override
  int compareTo(PartialDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) return byYear;
    final byMonth = (month ?? 0).compareTo(other.month ?? 0);
    if (byMonth != 0) return byMonth;
    return (day ?? 0).compareTo(other.day ?? 0);
  }

  /// ISO 8601, reduced to the known parts: `1985-03-12`, `1985-03`, `1985`.
  @override
  String toString() {
    final buffer = StringBuffer(year.toString().padLeft(4, '0'));
    if (month != null) buffer.write('-${month.toString().padLeft(2, '0')}');
    if (day != null) buffer.write('-${day.toString().padLeft(2, '0')}');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is PartialDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;
