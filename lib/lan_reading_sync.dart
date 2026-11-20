import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';

/// Nearby reading is omitted. Shelf progress on this device is unchanged.
class LanHandoffReceipt {
  const LanHandoffReceipt({this.online});
  final Object? online;
}

class LanResolvedBook {
  const LanResolvedBook({required this.book, required this.position});
  final Novel book;
  final ReadingPosition position;
}

class LanBookHandoff extends ChangeNotifier {
  LanHandoffReceipt? received;

  Future<LanResolvedBook> resolveReceipt(LanHandoffReceipt receipt) async {
    throw const FormatException('局域网续读在此版本不可用');
  }

  void dismissReceipt() {
    received = null;
    notifyListeners();
  }
}

class LanReadingSync {
  LanReadingSync({
    required this.state,
    required this.preferences,
    required this.books,
    required this.repository,
  });

  final LibraryState state;
  final SharedPreferences preferences;
  final LocalBookStore? books;
  final NovelRepository repository;
  final handoff = LanBookHandoff();

  Future<void> initialize() async {}
  void dispose() => handoff.dispose();
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});
  final LanReadingSync? sync;

  static LanReadingSync? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LanSyncScope>()?.sync;

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => oldWidget.sync != sync;
}
