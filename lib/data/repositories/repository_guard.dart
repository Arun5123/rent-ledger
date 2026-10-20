import '../../core/errors/app_exception.dart';

/// Wraps repository bodies so platform exceptions never leak into the
/// presentation layer.
Future<T> guardAsync<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AppException {
    rethrow;
  } catch (error, stackTrace) {
    throw AppException.from(error, stackTrace);
  }
}
