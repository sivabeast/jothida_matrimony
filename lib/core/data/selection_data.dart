/// Structured selection data for profile creation/editing — drives the
/// searchable & dependent (Religion → Caste → Sub-caste) dropdowns.
///
/// Keep flat lists (education, occupation, rasi…) in `AppConstants`; this file
/// holds the *hierarchical* data.
class SelectionData {
  // ── Religion → Castes ────────────────────────────────────────────────────
  static const Map<String, List<String>> castesByReligion = {
    'Hindu': [
      'Iyer', 'Iyengar', 'Vanniyar', 'Mudaliar', 'Nadar', 'Chettiar',
      'Gounder', 'Thevar', 'Pillai', 'Kongu Vellalar', 'Naidu', 'Reddy',
      'Brahmin', 'Yadava', 'Vishwakarma', 'Maravar', 'Agamudayar',
      'Senguntha Mudaliar', 'Adi Dravidar', 'Other',
    ],
    'Muslim': [
      'Sunni', 'Shia', 'Lebbai', 'Rowther', 'Marakkayar', 'Dudekula', 'Other',
    ],
    'Christian': [
      'Roman Catholic', 'Protestant', 'CSI', 'Born Again', 'Marthoma',
      'Pentecostal', 'Adventist', 'Other',
    ],
    'Sikh': ['Jat', 'Khatri', 'Arora', 'Ramgarhia', 'Other'],
    'Jain': ['Digambar', 'Svetambar', 'Other'],
    'Buddhist': ['Other'],
    'Other': ['Other'],
  };

  // ── Caste → Sub-castes ───────────────────────────────────────────────────
  static const Map<String, List<String>> subCastesByCaste = {
    'Iyer': ['Vadama', 'Brahacharanam', 'Vathima', 'Ashtasahasram', 'Other'],
    'Iyengar': ['Vadakalai', 'Thenkalai', 'Other'],
    'Vanniyar': ['Gounder', 'Padayachi', 'Naicker', 'Vanniya Kula Kshatriya', 'Other'],
    'Mudaliar': ['Thuluva Vellalar', 'Saiva', 'Sengunthar', 'Arcot', 'Other'],
    'Nadar': ['Hindu Nadar', 'Christian Nadar', 'Gramani', 'Other'],
    'Chettiar': ['Nattukottai', 'Devanga', 'Beri', 'Vaniya', 'Elur', 'Other'],
    'Gounder': ['Kongu Vellala Gounder', 'Vettuva Gounder', 'Nattu Gounder', 'Other'],
    'Thevar': ['Agamudayar', 'Maravar', 'Kallar', 'Other'],
    'Pillai': ['Saiva Pillai', 'Vellalar', 'Karkarthar', 'Other'],
    'Naidu': ['Balija', 'Kamma', 'Gavara', 'Telaga', 'Other'],
    'Reddy': ['Desai', 'Gandla', 'Other'],
  };

  /// Castes available for a [religion] (falls back to ['Other']).
  static List<String> castesFor(String? religion) =>
      castesByReligion[religion] ?? const ['Other'];

  /// Sub-castes available for a [caste] (falls back to ['Other']).
  static List<String> subCastesFor(String? caste) =>
      subCastesByCaste[caste] ?? const ['Other'];

  // ── Country → States → Cities ────────────────────────────────────────────
  static const List<String> countries = ['India', 'Sri Lanka', 'Malaysia',
    'Singapore', 'United States', 'United Kingdom', 'UAE', 'Canada', 'Australia', 'Other'];

  static const List<String> indianStates = [
    'Tamil Nadu', 'Kerala', 'Karnataka', 'Andhra Pradesh', 'Telangana',
    'Maharashtra', 'Delhi', 'Puducherry', 'Gujarat', 'West Bengal', 'Other',
  ];

  static const Map<String, List<String>> citiesByState = {
    'Tamil Nadu': [
      'Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem', 'Erode',
      'Tirunelveli', 'Vellore', 'Thoothukudi', 'Dindigul', 'Thanjavur',
      'Karur', 'Namakkal', 'Cuddalore', 'Other',
    ],
    'Kerala': ['Thiruvananthapuram', 'Kochi', 'Kozhikode', 'Thrissur', 'Other'],
    'Karnataka': ['Bangalore', 'Mysore', 'Mangalore', 'Hubli', 'Other'],
    'Andhra Pradesh': ['Visakhapatnam', 'Vijayawada', 'Guntur', 'Tirupati', 'Other'],
    'Telangana': ['Hyderabad', 'Warangal', 'Karimnagar', 'Other'],
    'Maharashtra': ['Mumbai', 'Pune', 'Nagpur', 'Nashik', 'Other'],
    'Delhi': ['New Delhi', 'Delhi', 'Other'],
    'Puducherry': ['Puducherry', 'Karaikal', 'Other'],
  };

  /// Cities for a [state] (falls back to a generic list).
  static List<String> citiesFor(String? state) =>
      citiesByState[state] ?? const ['Other'];

  /// A flat, de-duplicated, sorted list of all known cities — used for the
  /// "Birth Place" searchable picker.
  static List<String> get allCities {
    final set = <String>{};
    for (final list in citiesByState.values) {
      set.addAll(list.where((c) => c != 'Other'));
    }
    final result = set.toList()..sort();
    return result;
  }
}
