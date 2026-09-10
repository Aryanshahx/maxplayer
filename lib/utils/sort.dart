import 'settings.dart';

export 'settings.dart' show GroupBy, SortField, ViewMode;

/// Pure comparators for video sorting (unit-tested).

int cmpNum(num a, num b, bool asc) => asc ? a.compareTo(b) : b.compareTo(a);

int cmpStr(String a, String b, bool asc) =>
    asc ? a.toLowerCase().compareTo(b.toLowerCase())
        : b.toLowerCase().compareTo(a.toLowerCase());

/// Direction pill labels shown next to each sort field (design reference).
String sortDirectionLabel(SortField f, bool asc) => switch (f) {
      SortField.name => asc ? 'A → Z' : 'Z → A',
      SortField.dateAdded => asc ? 'Oldest first' : 'Newest first',
      SortField.size => asc ? 'Smallest first' : 'Largest first',
      SortField.length => asc ? 'Shortest first' : 'Longest first',
    };

String sortFieldLabel(SortField f) => switch (f) {
      SortField.name => 'Name',
      SortField.dateAdded => 'Date Added',
      SortField.size => 'File Size',
      SortField.length => 'Video Length',
    };

String groupByLabel(GroupBy g) => switch (g) {
      GroupBy.none => 'None',
      GroupBy.folder => 'Folder',
    };
