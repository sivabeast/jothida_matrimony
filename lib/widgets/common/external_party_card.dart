import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'horoscope_documents_view.dart';

/// Displays one party of an EXTERNAL horoscope report (spec §4) — the
/// manually-entered details + the uploaded horoscope image/PDF (reusing
/// [HoroscopeDocumentsView] for a consistent view/download experience).
///
/// Used on both employee report screens for the requester and the second
/// (non-registered) person, whose data is stored in
/// `AstrologerRequestModel.externalRequester` / `.externalOther` rather than in
/// a profile document.
class ExternalPartyCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Map<String, dynamic> data;
  const ExternalPartyCard({
    super.key,
    required this.title,
    required this.icon,
    required this.data,
  });

  String _s(String key) => (data[key] ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final image = _s('horoscopeImageUrl');
    final pdf = _s('horoscopePdfUrl');
    final age = _s('age');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                    Text(_s('name').isEmpty ? '—' : _s('name'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _row('Age', age.isEmpty || age == '0' ? '—' : '$age yrs'),
          _row('Gender', _s('gender')),
          _row('Date of Birth', _s('dob')),
          _row('Time of Birth', _s('tob')),
          _row('Place of Birth', _s('place')),
          _row('Nakshatra', _s('nakshatra')),
          _row('Rasi', _s('rasi')),
          if (image.isNotEmpty || pdf.isNotEmpty) ...[
            const SizedBox(height: 12),
            HoroscopeDocumentsView(
              imageUrls: [if (image.isNotEmpty) image],
              pdfUrls: [if (pdf.isNotEmpty) pdf],
              title: 'Horoscope Document',
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No horoscope document uploaded.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label,
                    style:
                        TextStyle(color: Colors.grey[600], fontSize: 12.5))),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ],
        ),
      );
}
