/// Penyimpanan antrean tulis offline, dipilih per platform.
library;

export 'outbox_store_stub.dart' if (dart.library.io) 'outbox_store_io.dart'
    show readOutbox, writeOutbox;
