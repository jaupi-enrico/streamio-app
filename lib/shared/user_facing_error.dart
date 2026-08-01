/// Marker for errors whose [message] is written for a user to read, so error
/// UI can show it verbatim instead of falling back to "something went wrong".
///
/// Anything not implementing this — a raw socket error, a type error — gets
/// the generic message, because its text is for a developer, not a viewer.
abstract interface class UserFacingError {
  String get message;
}
