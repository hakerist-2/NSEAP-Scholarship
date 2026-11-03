const List<String> kLalloBarangays = [
  'Abagao, Lal-lo, Cagayan',
  'Alaguia, Lal-lo, Cagayan',
  'Bagumbayan, Lal-lo, Cagayan',
  'Bangag, Lal-lo, Cagayan',
  'Bical, Lal-lo, Cagayan',
  'Bicud, Lal-lo, Cagayan',
  'Binag, Lal-lo, Cagayan',
  'Cabayabasan (Capacuan), Lal-lo, Cagayan',
  'Cagoran, Lal-lo, Cagayan',
  'Cambong, Lal-lo, Cagayan',
  'Catayauan, Lal-lo, Cagayan',
  'Catugan, Lal-lo, Cagayan',
  'Centro (Poblacion), Lal-lo, Cagayan',
  'Cullit, Lal-lo, Cagayan',
  'Dagupan, Lal-lo, Cagayan',
  'Dalaya, Lal-lo, Cagayan',
  'Fabrica, Lal-lo, Cagayan',
  'Fusina, Lal-lo, Cagayan',
  'Jurisdiction, Lal-lo, Cagayan',
  'Lalafugan, Lal-lo, Cagayan',
  'Logac, Lal-lo, Cagayan',
  'Magallungon (Santa Teresa), Lal-lo, Cagayan',
  'Magapit, Lal-lo, Cagayan',
  'Malanao, Lal-lo, Cagayan',
  'Maxingal, Lal-lo, Cagayan',
  'Naguilian, Lal-lo, Cagayan',
  'Paranum, Lal-lo, Cagayan',
  'Rosario, Lal-lo, Cagayan',
  'San Antonio (Lafu), Lal-lo, Cagayan',
  'San Jose, Lal-lo, Cagayan',
  'San Juan, Lal-lo, Cagayan',
  'San Lorenzo, Lal-lo, Cagayan',
  'San Mariano, Lal-lo, Cagayan',
  'Santa Maria, Lal-lo, Cagayan',
  'Tucalana, Lal-lo, Cagayan',
];

Future<List<String>> searchLalloBarangays(String query) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  // For single char, only startsWith to keep list small and avoid ANR
  // (overlay ListView + keyboard). For 2+ chars, rank startsWith first.
  final starts = kLalloBarangays
      .where((b) => b.toLowerCase().startsWith(q))
      .toList();
  if (q.length == 1) {
    // Cap to 8 to keep overlay light and scroll smooth.
    if (starts.length > 8) return starts.sublist(0, 8);
    return starts;
  }
  final contains = kLalloBarangays
      .where(
        (b) => !b.toLowerCase().startsWith(q) && b.toLowerCase().contains(q),
      )
      .toList();
  final combined = [...starts, ...contains];
  if (combined.length > 12) return combined.sublist(0, 12);
  return combined;
}
