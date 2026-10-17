/// Konfigurasi koneksi database.
///
/// Prioritas:
/// 1. Nilai yang diisi user lewat menu Pengaturan di aplikasi (tersimpan aman di HP).
/// 2. Compile-time: --dart-define=NEON_URL=postgresql://...
/// 3. Placeholder di bawah (ganti langsung di sini kalau mau hardcode untuk dev saja).
const kNeonUrlPlaceholder = String.fromEnvironment(
  'NEON_URL',
  defaultValue: 'postgresql://user:password@ep-cool-name-123456.ap-southeast-1.aws.neon.tech/neondb?sslmode=require',
);
