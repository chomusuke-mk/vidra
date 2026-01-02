import 'package:vidra/data/preferences/preference_options.dart';

const Set<String> kMapTextKeys = {'add_headers'};
const Set<String> kNumericTextKeys = {'two_factor', 'fragment_retries'};

List<String> filterMapKeySuggestions(
  List<String> availableOptions,
  Map<String, String> currentEntries, {
  required String query,
  required String currentInput,
}) {
  final trimmedQuery = query.trim().toLowerCase();
  final normalizedCurrent = currentInput.trim().toLowerCase();

  final usedKeys = currentEntries.keys
      .map((key) => key.trim().toLowerCase())
      .where((key) => key.isNotEmpty && key != normalizedCurrent)
      .toSet();

  return availableOptions
      .where((option) {
        final optionLower = option.toLowerCase();
        if (usedKeys.contains(optionLower)) {
          return false;
        }
        if (trimmedQuery.isEmpty) {
          return true;
        }
        return optionLower.contains(trimmedQuery);
      })
      .toList(growable: false);
}

class SpinnerState {
  SpinnerState(IntegerSpinnerConfig config)
    : step = config.step <= 0 ? 1 : config.step,
      defaultMinInt = _resolveDefaultMin(config.minSequence),
      descendingMinStops = _resolveDescendingMinStops(
        config.minSequence,
        _resolveDefaultMin(config.minSequence),
      ),
      defaultMaxInt = _resolveDefaultMax(config.maxSequence),
      ascendingMaxStops = _resolveAscendingMaxStops(
        config.maxSequence,
        _resolveDefaultMax(config.maxSequence),
      ),
      normalizedStrings = _resolveNormalizedStrings(config);

  final int step;
  final int defaultMinInt;
  final int? defaultMaxInt;
  final List<Object> descendingMinStops;
  final List<Object> ascendingMaxStops;
  final Map<String, String> normalizedStrings;

  static int _resolveDefaultMin(List<Object> minSequence) {
    final ints = minSequence.whereType<int>().toList()..sort();
    if (ints.isEmpty) {
      return 0;
    }
    return ints.last;
  }

  static List<Object> _resolveDescendingMinStops(
    List<Object> minSequence,
    int defaultMin,
  ) {
    final seen = <Object>{};
    final stops = <Object>[];
    for (final value in minSequence.reversed) {
      if (value is int) {
        if (value < defaultMin && seen.add(value)) {
          stops.add(value);
        }
      } else if (seen.add(value)) {
        stops.add(value);
      }
    }
    return stops;
  }

  static int? _resolveDefaultMax(List<Object> maxSequence) {
    final ints = maxSequence.whereType<int>().toList()..sort();
    if (ints.isEmpty) {
      return null;
    }
    return ints.first;
  }

  static List<Object> _resolveAscendingMaxStops(
    List<Object> maxSequence,
    int? defaultMax,
  ) {
    if (maxSequence.isEmpty) {
      return const <Object>[];
    }
    final seen = <Object>{};
    final stops = <Object>[];
    for (final value in maxSequence) {
      if (value is int && defaultMax != null && value == defaultMax) {
        continue;
      }
      if (seen.add(value)) {
        stops.add(value);
      }
    }
    return stops;
  }

  static Map<String, String> _resolveNormalizedStrings(
    IntegerSpinnerConfig config,
  ) {
    final result = <String, String>{};
    for (final entry in config.minSequence) {
      if (entry is String) {
        result.putIfAbsent(entry.toLowerCase(), () => entry);
      }
    }
    for (final entry in config.maxSequence) {
      if (entry is String) {
        result.putIfAbsent(entry.toLowerCase(), () => entry);
      }
    }
    return result;
  }

  Object? parse(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsedInt = int.tryParse(trimmed);
    if (parsedInt != null) {
      return normalizeValue(parsedInt);
    }
    final lowered = trimmed.toLowerCase();
    if (normalizedStrings.containsKey(lowered)) {
      return normalizedStrings[lowered];
    }
    return null;
  }

  Object? normalizeValue(Object? value) {
    if (value is int) {
      if (descendingMinStops.contains(value)) {
        return value;
      }
      if (defaultMaxInt != null && ascendingMaxStops.contains(value)) {
        return value;
      }
      if (value < defaultMinInt) {
        if (descendingMinStops.isNotEmpty) {
          return descendingMinStops.last;
        }
        return defaultMinInt;
      }
      if (defaultMaxInt != null && value > defaultMaxInt!) {
        if (ascendingMaxStops.isNotEmpty) {
          for (final stop in ascendingMaxStops) {
            if (stop is int && stop <= value) {
              return stop;
            }
            if (stop is String) {
              final lowered = stop.toLowerCase();
              if (normalizedStrings.containsKey(lowered)) {
                return normalizedStrings[lowered];
              }
            }
          }
        }
        return defaultMaxInt!;
      }
      return value;
    }
    if (value is String) {
      final lowered = value.toLowerCase();
      if (normalizedStrings.containsKey(lowered)) {
        return normalizedStrings[lowered];
      }
      return null;
    }
    return null;
  }

  Object format(Object value) => value;

  Object stepValue(Object current, int delta) {
    var normalized = normalizeValue(current) ?? defaultMinInt;
    if (delta == 0) {
      return normalized;
    }
    if (delta > 0) {
      normalized = _stepUp(normalized);
    } else {
      normalized = _stepDown(normalized);
    }
    return normalizeValue(normalized) ?? defaultMinInt;
  }

  Object _stepDown(Object current) {
    if (current is String) {
      final minIndex = descendingMinStops.indexOf(current);
      if (minIndex != -1) {
        if (minIndex + 1 < descendingMinStops.length) {
          return descendingMinStops[minIndex + 1];
        }
        return descendingMinStops[minIndex];
      }
      final maxIndex = ascendingMaxStops.indexOf(current);
      if (maxIndex != -1) {
        if (maxIndex + 1 < ascendingMaxStops.length) {
          return ascendingMaxStops[maxIndex + 1];
        }
        return ascendingMaxStops[maxIndex];
      }
      return current;
    }

    if (current is int) {
      if (current > defaultMinInt) {
        final candidate = current - step;
        if (candidate >= defaultMinInt) {
          return candidate;
        }
        if (descendingMinStops.isNotEmpty) {
          return descendingMinStops.first;
        }
        return defaultMinInt;
      }

      if (current == defaultMinInt) {
        if (descendingMinStops.isNotEmpty) {
          return descendingMinStops.first;
        }
        return defaultMinInt;
      }

      final index = descendingMinStops.indexOf(current);
      if (index != -1) {
        if (index + 1 < descendingMinStops.length) {
          return descendingMinStops[index + 1];
        }
        return descendingMinStops[index];
      }

      return defaultMinInt;
    }

    return defaultMinInt;
  }

  Object _stepUp(Object current) {
    if (current is String) {
      final minIndex = descendingMinStops.indexOf(current);
      if (minIndex != -1) {
        if (minIndex == 0) {
          return defaultMinInt;
        }
        return descendingMinStops[minIndex - 1];
      }
      final maxIndex = ascendingMaxStops.indexOf(current);
      if (maxIndex != -1) {
        if (maxIndex + 1 < ascendingMaxStops.length) {
          return ascendingMaxStops[maxIndex + 1];
        }
        return ascendingMaxStops[maxIndex];
      }
      return current;
    }

    if (current is int) {
      final minIndex = descendingMinStops.indexOf(current);
      if (minIndex != -1) {
        if (minIndex == 0) {
          return defaultMinInt;
        }
        return descendingMinStops[minIndex - 1];
      }

      if (defaultMaxInt == null) {
        return current + step;
      }

      if (current < defaultMaxInt!) {
        final candidate = current + step;
        if (candidate <= defaultMaxInt!) {
          return candidate;
        }
        if (ascendingMaxStops.isNotEmpty) {
          return ascendingMaxStops.first;
        }
        return defaultMaxInt!;
      }

      if (current == defaultMaxInt!) {
        if (ascendingMaxStops.isNotEmpty) {
          return ascendingMaxStops.first;
        }
        return defaultMaxInt!;
      }

      final index = ascendingMaxStops.indexOf(current);
      if (index != -1) {
        if (index + 1 < ascendingMaxStops.length) {
          return ascendingMaxStops[index + 1];
        }
        return ascendingMaxStops[index];
      }

      return current + step;
    }

    return defaultMinInt;
  }
}

bool isPotentialSpinnerInput(SpinnerState spinnerState, String trimmed) {
  if (trimmed.isEmpty) {
    return true;
  }

  final numericPattern = RegExp(r'^-?\d*$');
  if (numericPattern.hasMatch(trimmed)) {
    if (trimmed == '-') {
      return spinnerState.descendingMinStops.any((value) {
        if (value is int) {
          return true;
        }
        if (value is String) {
          return spinnerState.normalizedStrings.containsKey(
            value.toLowerCase(),
          );
        }
        return false;
      });
    }
    return true;
  }

  final lower = trimmed.toLowerCase();
  for (final option in spinnerState.normalizedStrings.values) {
    if (option.toLowerCase().startsWith(lower)) {
      return true;
    }
  }
  return false;
}
