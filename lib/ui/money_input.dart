/// Input nominal uang dengan pemisah ribuan otomatis.
///
/// Kenapa perlu: sebelumnya kolom nominal hanya menerima angka mentah
/// ("350000"), dan pengguna harus menghitung sendiri jumlah nolnya. Salah satu
/// nol berarti uang yang tercatat 10× lipat, dan itu tidak terlihat sampai
/// laporan kasnya diperiksa. Sekarang titik muncul sendiri tiap 3 digit
/// ("350.000"), sama seperti yang ditampilkan di seluruh aplikasi.
///
/// Yang ditangani:
///   * titik ribuan otomatis saat mengetik, dan ikut hilang saat menghapus;
///   * posisi kursor tidak meloncat (dihitung dari jumlah digit di kiri kursor,
///     bukan dari indeks karakter — karena jumlah titik berubah);
///   * koma untuk sen (maks. 2 digit), mengikuti kebiasaan Indonesia;
///   * tempel (paste) "Rp 1.500.000" atau "1500000" sama-sama jadi "1.500.000";
///   * nol di depan dibuang ("05" → "5"), tapi "0" sendiri tetap boleh.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'fmt.dart';

/// Format angka jadi bertitik: `1500000` → `1.500.000`.
String groupThousands(String digits) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Hitung berapa digit (0-9) sebelum posisi [cursor] pada [text].
int _digitsBefore(String text, int cursor) {
  var n = 0;
  for (var i = 0; i < cursor && i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c >= 0x30 && c <= 0x39) n++;
  }
  return n;
}

/// Ubah teks mentah jadi bentuk tampilan: `1.500.000` atau `1.500.000,50`.
///
/// Aturan pemisah mengikuti tampilan aplikasi, bukan tebakan:
///   * **titik selalu pemisah ribuan** — dibuang lalu dipasang ulang oleh
///     formatter. Ini juga yang membuat mengetik/menempel "1.500.000" dan
///     "1500000" menghasilkan hal yang sama;
///   * **koma selalu pemisah sen** (maks. 2 digit), sesuai kebiasaan Indonesia.
///
/// [hadDecimal] false untuk kolom bilangan bulat: koma diabaikan sepenuhnya.
String formatMoneyText(String raw, {bool hadDecimal = true}) {
  var digits = '';
  var decimals = '';
  var seenComma = false;
  for (final ch in raw.split('')) {
    final isDigit = ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;
    if (isDigit) {
      if (seenComma) {
        if (decimals.length < 2) decimals += ch;
      } else {
        digits += ch;
      }
    } else if (ch == ',' && !hadDecimal) {
      // Kolom bilangan bulat: koma mengakhiri angka. Digit setelahnya bukan
      // bagian dari nilai ("1.500,50" pada kolom jumlah berarti 1.500).
      break;
    } else if (ch == ',' && !seenComma && digits.isNotEmpty) {
      seenComma = true;
    }
    // Titik dan karakter lain diabaikan: titik adalah pemisah ribuan yang
    // akan dipasang ulang di bawah.
  }

  // Nol di depan tidak berguna dan membuat lebar kolom melompat.
  digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  if (digits.isEmpty && !seenComma) return '';
  if (digits.isEmpty) digits = '0';

  final body = groupThousands(digits);
  if (!seenComma) return body;
  return '$body,$decimals';
}

/// [TextInputFormatter] yang memformat nominal saat diketik.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({this.allowDecimal = true});

  /// Kolom bilangan bulat (jumlah, nomor) tidak perlu koma.
  final bool allowDecimal;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;

    // Hitung digit di kiri kursor SEBELUM diformat ulang.
    final digitsBefore = _digitsBefore(raw, newValue.selection.baseOffset.clamp(0, raw.length));

    final formatted = formatMoneyText(raw, hadDecimal: allowDecimal);
    if (formatted.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Tempatkan kursor setelah jumlah digit yang sama di teks baru.
    var seen = 0;
    var offset = formatted.length;
    for (var i = 0; i < formatted.length; i++) {
      final c = formatted.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      if (isDigit) {
        seen++;
        if (seen == digitsBefore) {
          offset = i + 1;
          break;
        }
      }
    }
    if (digitsBefore == 0) offset = 0;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset.clamp(0, formatted.length)),
    );
  }
}

/// Baca nominal dari teks yang sudah diformat ("1.500.000" / "1.500.000,50").
///
/// Berbeda dari `parseMoney` yang menerima banyak gaya ketikan, di sini
/// formatnya sudah pasti hasil [MoneyInputFormatter] — jadi titik pasti ribuan
/// dan koma pasti desimal. Dipakai form supaya tidak ada tebakan kedua.
double parseFormattedMoney(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return 0;
  final parts = clean.split(',');
  final whole = parts.first.replaceAll('.', '').replaceAll(RegExp(r'[^0-9]'), '');
  var value = double.tryParse(whole) ?? 0;
  if (parts.length > 1) {
    final frac = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
    if (frac.isNotEmpty) {
      value += (double.tryParse(frac.padRight(2, '0').substring(0, 2)) ?? 0) / 100;
    }
  }
  return value;
}

/// Kolom nominal rupiah: titik ribuan otomatis + konfirmasi "Terbaca: Rp …".
///
/// Konfirmasi itu penting. Dengan format ribuan, "150.000" dan "1.500.000"
/// terlihat mirip sekilas; salah satu nol baru ketahuan setelah buku kas
/// terisi, dan koreksinya berarti hapus + catat ulang. Baris bantu di bawah
/// kolom menampilkan nilai yang benar-benar akan disimpan.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.controller,
    this.placeholder = const Text('Nominal'),
    this.autofocus = false,
    this.textInputAction,
  });

  final TextEditingController controller;
  final Widget placeholder;
  final bool autofocus;
  final TextInputAction? textInputAction;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  double _value = 0;

  @override
  void initState() {
    super.initState();
    _value = parseFormattedMoney(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final v = parseFormattedMoney(widget.controller.text);
    if (v != _value && mounted) setState(() => _value = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShadInput(
          controller: widget.controller,
          placeholder: widget.placeholder,
          autofocus: widget.autofocus,
          textInputAction: widget.textInputAction,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [MoneyInputFormatter(allowDecimal: false)],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
          child: Text(
            _value > 0
                ? 'Terbaca: ${fmtMoney(_value)}'
                : 'Ketik angka — titik ribuan muncul sendiri',
            style: t.textTheme.small.copyWith(
              color: _value > 0 ? t.colorScheme.primary : t.colorScheme.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tombol simpan dengan indikator proses.
///
/// Sebelumnya hanya dua dari tujuh dialog yang menampilkan spinner; sisanya
/// hanya menonaktifkan tombol tanpa tanda apa pun, sehingga di jaringan lambat
/// dialog terlihat beku dan pengguna menutup paksa lalu mengulang — menghasilkan
/// data ganda. Satu widget ini dipakai semua dialog supaya perilakunya seragam.
class SaveButton extends StatelessWidget {
  const SaveButton({
    super.key,
    required this.saving,
    required this.onPressed,
    this.label = 'Simpan',
  });

  final bool saving;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ShadButton(
      onPressed: saving ? null : onPressed,
      child: saving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
