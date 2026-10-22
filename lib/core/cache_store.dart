/// Cache store aktif, dipilih per platform dan bisa diganti di tes.
library;

import 'package:flutter/foundation.dart';

import 'cache.dart';
import 'cache_stub.dart' if (dart.library.io) 'cache_io.dart' show createCacheStore;

/// Store yang dipakai `Db`. Tes menggantinya dengan versi memori supaya
/// penambalan cache bisa diuji tanpa filesystem/localStorage.
CacheStore activeCacheStore = createCacheStore();

@visibleForTesting
void useCacheStore(CacheStore store) => activeCacheStore = store;

@visibleForTesting
void resetCacheStore() => activeCacheStore = createCacheStore();
