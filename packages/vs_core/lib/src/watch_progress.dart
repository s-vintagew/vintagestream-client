import 'package:shared_preferences/shared_preferences.dart';

class WatchProgressStore {
  WatchProgressStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'pos:';

  static Future<WatchProgressStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return WatchProgressStore(prefs);
  }

  Duration? getPosition(String mediaId) {
    final ms = _prefs.getInt('$_prefix$mediaId');
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  Future<void> savePosition(String mediaId, Duration position, Duration? duration) async {
    if (position.inSeconds < 5) {
      await clear(mediaId);
      return;
    }
    if (duration != null && duration.inSeconds > 0) {
      final remaining = duration - position;
      if (remaining.inSeconds < 20) {
        await clear(mediaId);
        return;
      }
    }
    await _prefs.setInt('$_prefix$mediaId', position.inMilliseconds);
  }

  Future<void> clear(String mediaId) => _prefs.remove('$_prefix$mediaId');
}
