import 'dart:math';

enum QueueRepeat { off, all, one }

/// Pure queue traversal model. Shuffle visits each slot once per cycle; previous
/// follows actual playback history instead of choosing another random item.
class QueueOrder {
  final Random random;
  QueueOrder({Random? random}) : random = random ?? Random();
  bool shuffle = false;
  QueueRepeat repeat = QueueRepeat.off;
  final List<int> _history = [];
  final List<int> _bag = [];
  int _length = 0;
  int? _current;
  void reset(int length, {int? current}) {
    _length = length;
    _current = current;
    _history.clear();
    _refill();
  }

  void setShuffle(bool enabled, {required int current, required int length}) {
    shuffle = enabled;
    reset(length, current: current);
  }

  void select(int index, int length) {
    if (_length != length) reset(length, current: _current);
    if (_current != null && _current != index) _history.add(_current!);
    if (_history.length > 1000) _history.removeAt(0);
    _current = index;
    _bag.remove(index);
  }

  void _refill() {
    _bag
      ..clear()
      ..addAll(List.generate(_length, (i) => i).where((i) => i != _current));
    _bag.shuffle(random);
  }

  bool hasNext(int current, int length) {
    if (length <= 0 || current < 0 || current >= length) return false;
    return repeat == QueueRepeat.all ||
        (shuffle
            ? (_length != length ? length > 1 : _bag.any((i) => i != current))
            : current + 1 < length);
  }

  bool hasPrevious(int current, int length) =>
      length > 0 &&
      current >= 0 &&
      (shuffle
          ? _history.isNotEmpty
          : current > 0 || repeat == QueueRepeat.all);
  int? next(int current, int length, {bool completed = false}) {
    if (length <= 0 || current < 0 || current >= length) return null;
    if (_length != length) reset(length, current: current);
    if (completed && repeat == QueueRepeat.one) return current;
    if (shuffle) {
      _bag.remove(current);
      if (_bag.isEmpty) {
        if (repeat != QueueRepeat.all) return null;
        _refill();
        if (_bag.isEmpty) return current;
      }
      return _bag.first;
    }
    if (current + 1 < length) return current + 1;
    return repeat == QueueRepeat.all ? 0 : null;
  }

  int? previous(int current, int length) {
    if (length <= 0 || current < 0 || current >= length) return null;
    if (_length != length) reset(length, current: current);
    if (shuffle) {
      if (_history.isEmpty) return null;
      final target = _history.removeLast();
      _current = target;
      if (!_bag.contains(current)) _bag.insert(0, current);
      return target;
    }
    if (current > 0) return current - 1;
    return repeat == QueueRepeat.all ? length - 1 : null;
  }
}
