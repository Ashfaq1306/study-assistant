/// "Now" according to the server, learned from the `X-Server-Time` header on
/// every response. Countdowns use this so a wrong phone clock cannot shorten a
/// study session.
class ServerClock {
  Duration _offset = Duration.zero;

  DateTime now() => DateTime.now().add(_offset);

  void observe(String? header) {
    final server = DateTime.tryParse(header ?? '');
    if (server != null) _offset = server.difference(DateTime.now());
  }
}
