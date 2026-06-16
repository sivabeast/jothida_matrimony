/// Phone-number helpers for launching Call / WhatsApp / SMS actions.
///
/// Numbers are stored in many shapes (`8870846688`, `+91 88708 46688`,
/// `91-8870846688`…). Before building a `tel:`, `sms:` or `wa.me` link we
/// normalise to the Indian form (country code **91**) so the link always
/// resolves — fixing WhatsApp's "missing/ wrong country code" error.
library;

/// Normalises [phone] to a digits-only Indian number (country code `91`, no
/// `+`).
///
/// Steps:
///  1. Strip everything that isn't a digit — spaces, hyphens, brackets, dots
///     and a leading `+` all go.
///  2. Drop an international-access `00` prefix (e.g. `0091…`).
///  3. Drop a domestic trunk `0` in front of a 10-digit number (`08870…`).
///  4. A bare 10-digit number → prepend `91`.
///  5. A 12-digit number already starting with `91` (or anything else) → kept
///     as-is.
///
/// Examples:
///  * `8870846688`        → `918870846688`
///  * `91 8870846688`     → `918870846688`
///  * `+91-88708 46688`   → `918870846688`
///  * `08870846688`       → `918870846688`
///
/// Never throws; an empty/garbage input returns `''`.
String normalizeIndianPhone(String phone) {
  // 1) Keep digits only (removes spaces, hyphens, brackets, dots, '+', …).
  var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  // 2) International access code 00 → drop it (0091… → 91…).
  if (digits.startsWith('00')) digits = digits.substring(2);

  // 3) Domestic trunk 0 + 10 digits → strip the 0.
  if (digits.length == 11 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }

  // 4) Bare 10-digit local number → add the country code.
  if (digits.length == 10) return '91$digits';

  // 5) Already 91-prefixed (or some other already-qualified form) → as-is.
  return digits;
}

/// E.164 form (`+<digits>`) used for `tel:` and `sms:` links. `''` if empty.
String toE164(String phone) {
  final n = normalizeIndianPhone(phone);
  return n.isEmpty ? '' : '+$n';
}

/// Human-friendly display form, e.g. `+91 98765 43210`. Falls back to the plain
/// E.164 string for numbers that aren't a 12-digit `91…` value.
String formatIndianPhoneDisplay(String phone) {
  final n = normalizeIndianPhone(phone);
  if (n.length == 12 && n.startsWith('91')) {
    final local = n.substring(2);
    return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
  }
  return toE164(phone);
}

/// `tel:+91…` URI for a phone call.
Uri phoneCallUri(String phone) => Uri.parse('tel:${toE164(phone)}');

/// `sms:+91…` URI for a text message.
Uri smsUri(String phone) => Uri.parse('sms:${toE164(phone)}');

/// `https://wa.me/91…` URI for WhatsApp (digits only — wa.me rejects a `+`).
Uri whatsappUri(String phone) =>
    Uri.parse('https://wa.me/${normalizeIndianPhone(phone)}');
