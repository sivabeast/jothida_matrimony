import 'package:flutter/material.dart';

/// Master Wedding Planning Template — the predefined, research-backed catalogue
/// of everything an Indian (especially Tamil / South Indian) family arranges
/// for a wedding, from planning to completion.
///
/// PRINCIPLE: this lists only what OUR FAMILY must arrange — bookings,
/// purchases, vendors, rituals. It deliberately excludes infrastructure that
/// belongs to the venue (dining hall, kitchen, bride room, parking, water,
/// rest rooms), because those are not planning tasks for the family.
///
/// The Planning page renders these categories; ticking an item auto-generates
/// a Task. Approved family-contributed custom items ([WeddingPlanCustomItem])
/// are merged on top of this list so the catalogue keeps improving.

/// A single predefined planning line item.
class WeddingPlanItem {
  final String key; // stable id: '<categoryKey>.<itemKey>'
  final String title;
  const WeddingPlanItem(this.key, this.title);
}

/// A planning category with its complete predefined item list.
class WeddingPlanCategory {
  final String key;
  final String name;
  final IconData icon;
  final List<WeddingPlanItem> items;
  const WeddingPlanCategory({
    required this.key,
    required this.name,
    required this.icon,
    required this.items,
  });
}

/// The complete master template.
const List<WeddingPlanCategory> kWeddingPlanTemplate = [
  // ── Venue ─────────────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'venue',
    name: 'Venue',
    icon: Icons.location_city_outlined,
    items: [
      WeddingPlanItem('venue.muhurtham', 'Muhurtham Date Finalization'),
      WeddingPlanItem('venue.hall', 'Marriage Hall Booking'),
      WeddingPlanItem('venue.mandapam', 'Kalyana Mandapam Booking'),
      WeddingPlanItem('venue.temple', 'Temple Booking'),
      WeddingPlanItem('venue.reception', 'Reception Hall Booking'),
      WeddingPlanItem('venue.engagement', 'Engagement Venue Booking'),
      WeddingPlanItem('venue.outdoor', 'Outdoor / Garden Venue'),
      WeddingPlanItem('venue.destination', 'Destination Venue'),
      WeddingPlanItem('venue.visit', 'Venue Visit & Inspection'),
      WeddingPlanItem('venue.advance', 'Venue Advance Payment'),
      WeddingPlanItem('venue.generator', 'Generator / Power Backup Booking'),
    ],
  ),

  // ── Food / Catering ───────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'food',
    name: 'Food',
    icon: Icons.restaurant_outlined,
    items: [
      WeddingPlanItem('food.caterer', 'Caterer Booking'),
      WeddingPlanItem('food.menu', 'Menu Finalization'),
      WeddingPlanItem('food.tasting', 'Food Tasting Session'),
      WeddingPlanItem('food.count', 'Guest Count (Plates) Confirmation'),
      WeddingPlanItem('food.tiffin', 'Breakfast / Tiffin Menu'),
      WeddingPlanItem('food.lunch', 'Lunch (Sappadu) Menu'),
      WeddingPlanItem('food.dinner', 'Dinner Menu'),
      WeddingPlanItem('food.sweets', 'Sweets & Snacks'),
      WeddingPlanItem('food.welcomedrink', 'Welcome Drinks'),
      WeddingPlanItem('food.livecounter', 'Live Counters'),
      WeddingPlanItem('food.coffee', 'Filter Coffee / Tea Stall'),
      WeddingPlanItem('food.special', 'Special / Jain / Diet Food'),
      WeddingPlanItem('food.water', 'Packaged Water Arrangement'),
      WeddingPlanItem('food.staff', 'Serving Staff Confirmation'),
      WeddingPlanItem('food.advance', 'Catering Advance Payment'),
    ],
  ),

  // ── Decoration ────────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'decoration',
    name: 'Decoration',
    icon: Icons.celebration_outlined,
    items: [
      WeddingPlanItem('decoration.decorator', 'Decorator Booking'),
      WeddingPlanItem('decoration.stage', 'Stage Decoration'),
      WeddingPlanItem('decoration.mandap', 'Mandap Decoration'),
      WeddingPlanItem('decoration.flower', 'Flower Decoration'),
      WeddingPlanItem('decoration.entrance', 'Entrance / Arch Decoration'),
      WeddingPlanItem('decoration.car', 'Car Decoration'),
      WeddingPlanItem('decoration.kolam', 'Kolam / Rangoli'),
      WeddingPlanItem('decoration.lighting', 'Lighting Decoration'),
      WeddingPlanItem('decoration.backdrop', 'Backdrop / Photo Booth'),
      WeddingPlanItem('decoration.reception', 'Reception Decoration'),
      WeddingPlanItem('decoration.table', 'Table Decoration'),
      WeddingPlanItem('decoration.poojadai', 'Poo Jadai (Hair Flowers)'),
      WeddingPlanItem('decoration.banana', 'Banana Trees & Kalasam'),
      WeddingPlanItem('decoration.advance', 'Decoration Advance Payment'),
    ],
  ),

  // ── Photography ───────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'photography',
    name: 'Photography',
    icon: Icons.photo_camera_outlined,
    items: [
      WeddingPlanItem('photography.photographer', 'Photographer Booking'),
      WeddingPlanItem('photography.candid', 'Candid Photography'),
      WeddingPlanItem('photography.traditional', 'Traditional Photography'),
      WeddingPlanItem('photography.prewedding', 'Pre-Wedding Shoot'),
      WeddingPlanItem('photography.engagement', 'Engagement Photography'),
      WeddingPlanItem('photography.reception', 'Reception Photography'),
      WeddingPlanItem('photography.album', 'Album Design Finalization'),
      WeddingPlanItem('photography.selection', 'Photo Selection'),
      WeddingPlanItem('photography.advance', 'Photography Advance Payment'),
    ],
  ),

  // ── Videography ───────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'videography',
    name: 'Videography',
    icon: Icons.videocam_outlined,
    items: [
      WeddingPlanItem('videography.videographer', 'Videographer Booking'),
      WeddingPlanItem('videography.traditional', 'Traditional Video'),
      WeddingPlanItem('videography.cinematic', 'Candid / Cinematic Video'),
      WeddingPlanItem('videography.drone', 'Drone Coverage'),
      WeddingPlanItem('videography.livestream', 'Live Streaming Setup'),
      WeddingPlanItem('videography.sde', 'Same-Day Edit'),
      WeddingPlanItem('videography.highlight', 'Highlight Video'),
      WeddingPlanItem('videography.advance', 'Videography Advance Payment'),
    ],
  ),

  // ── Music & Entertainment ─────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'music',
    name: 'Music',
    icon: Icons.music_note_outlined,
    items: [
      WeddingPlanItem('music.nadaswaram', 'Nadaswaram & Thavil Booking'),
      WeddingPlanItem('music.gettimelam', 'Getti Melam'),
      WeddingPlanItem('music.mangala', 'Mangala Vaathiyam'),
      WeddingPlanItem('music.dj', 'DJ Booking'),
      WeddingPlanItem('music.band', 'Live Band / Orchestra'),
      WeddingPlanItem('music.sangeet', 'Sangeet Program'),
      WeddingPlanItem('music.dance', 'Dance Program'),
      WeddingPlanItem('music.anchor', 'Anchor / Emcee'),
      WeddingPlanItem('music.sound', 'Sound System'),
      WeddingPlanItem('music.kids', 'Entertainment for Kids'),
    ],
  ),

  // ── Bride Preparation ─────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'bride',
    name: 'Bride Preparation',
    icon: Icons.face_3_outlined,
    items: [
      WeddingPlanItem('bride.makeup', 'Bridal Makeup Artist'),
      WeddingPlanItem('bride.mehendi', 'Mehendi Artist'),
      WeddingPlanItem('bride.koorai', 'Bridal Saree (Koorai / Kanjivaram)'),
      WeddingPlanItem('bride.blouse', 'Blouse Stitching'),
      WeddingPlanItem('bride.reception', 'Reception Dress'),
      WeddingPlanItem('bride.engagement', 'Engagement Dress'),
      WeddingPlanItem('bride.trial', 'Bridal Trial'),
      WeddingPlanItem('bride.hair', 'Hairstyle Trial'),
      WeddingPlanItem('bride.accessories', 'Bridal Accessories'),
      WeddingPlanItem('bride.footwear', 'Bridal Footwear'),
      WeddingPlanItem('bride.nalangu', 'Nalangu Items'),
      WeddingPlanItem('bride.prebridal', 'Pre-Bridal / Spa Package'),
    ],
  ),

  // ── Groom Preparation ─────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'groom',
    name: 'Groom Preparation',
    icon: Icons.face_outlined,
    items: [
      WeddingPlanItem('groom.veshti', 'Groom Dhoti / Veshti Purchase'),
      WeddingPlanItem('groom.shirt', 'Shirt / Kurta'),
      WeddingPlanItem('groom.suit', 'Reception Suit'),
      WeddingPlanItem('groom.grooming', 'Groom Grooming / Makeup'),
      WeddingPlanItem('groom.accessories', 'Accessories (Ring, Watch)'),
      WeddingPlanItem('groom.footwear', 'Groom Footwear'),
      WeddingPlanItem('groom.thalapa', 'Turban / Thalapa'),
      WeddingPlanItem('groom.trial', 'Groom Trial'),
    ],
  ),

  // ── Jewellery ─────────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'jewellery',
    name: 'Jewellery',
    icon: Icons.diamond_outlined,
    items: [
      WeddingPlanItem('jewellery.thali', 'Thali / Mangalsutra'),
      WeddingPlanItem('jewellery.thalikodi', 'Thali Kodi (Chain)'),
      WeddingPlanItem('jewellery.gold', 'Bridal Gold Jewellery'),
      WeddingPlanItem('jewellery.diamond', 'Diamond Jewellery'),
      WeddingPlanItem('jewellery.temple', 'Temple Jewellery (Rental)'),
      WeddingPlanItem('jewellery.bangles', 'Bangles / Valayal'),
      WeddingPlanItem('jewellery.metti', 'Metti (Toe Rings)'),
      WeddingPlanItem('jewellery.groomring', "Groom's Ring"),
      WeddingPlanItem('jewellery.engagement', 'Engagement Rings'),
      WeddingPlanItem('jewellery.silver', 'Silver Items (Pooja)'),
      WeddingPlanItem('jewellery.insurance', 'Jewellery Insurance'),
      WeddingPlanItem('jewellery.payment', 'Jewellery Purchase Payment'),
    ],
  ),

  // ── Invitation ────────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'invitation',
    name: 'Invitation',
    icon: Icons.mail_outline,
    items: [
      WeddingPlanItem('invitation.design', 'Invitation Card Design'),
      WeddingPlanItem('invitation.print', 'Card Printing'),
      WeddingPlanItem('invitation.digital', 'Digital / E-Invitation'),
      WeddingPlanItem('invitation.savedate', 'Save the Date'),
      WeddingPlanItem('invitation.guestlist', 'Guest List Finalization'),
      WeddingPlanItem('invitation.firstgod', 'First Invitation to Temple / God'),
      WeddingPlanItem('invitation.elders', 'Invitation to Elders'),
      WeddingPlanItem('invitation.whatsapp', 'WhatsApp Invitation'),
      WeddingPlanItem('invitation.distribute', 'Invitation Distribution'),
    ],
  ),

  // ── Transportation ────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'transportation',
    name: 'Transportation',
    icon: Icons.directions_car_outlined,
    items: [
      WeddingPlanItem('transportation.bridecar', 'Bride Car'),
      WeddingPlanItem('transportation.groomcar', 'Groom Car'),
      WeddingPlanItem('transportation.couplecar', 'Decorated Car for Couple'),
      WeddingPlanItem('transportation.guestbus', 'Guest Bus / Van Arrangement'),
      WeddingPlanItem('transportation.pickup', 'Outstation Guest Pickup'),
      WeddingPlanItem('transportation.airport', 'Airport / Station Pickup'),
      WeddingPlanItem('transportation.luggage', 'Luggage Transportation'),
      WeddingPlanItem('transportation.driver', 'Driver / Valet Arrangement'),
      WeddingPlanItem('transportation.fuel', 'Fuel & Toll Budget'),
    ],
  ),

  // ── Guest Management ──────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'guest',
    name: 'Guest Management',
    icon: Icons.groups_outlined,
    items: [
      WeddingPlanItem('guest.list', 'Guest List Preparation'),
      WeddingPlanItem('guest.rsvp', 'RSVP Tracking'),
      WeddingPlanItem('guest.vip', 'VIP Guest List'),
      WeddingPlanItem('guest.seating', 'Guest Seating Plan'),
      WeddingPlanItem('guest.welcome', 'Welcome Team Assignment'),
      WeddingPlanItem('guest.kits', 'Guest Kits'),
      WeddingPlanItem('guest.reception', 'Reception Guest List'),
      WeddingPlanItem('guest.outstation', 'Out-of-Town Guest Count'),
    ],
  ),

  // ── Accommodation ─────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'accommodation',
    name: 'Accommodation',
    icon: Icons.hotel_outlined,
    items: [
      WeddingPlanItem('accommodation.rooms', 'Guest Room Booking'),
      WeddingPlanItem('accommodation.family', 'Bride / Groom Family Stay'),
      WeddingPlanItem('accommodation.outstation', 'Outstation Guest Rooms'),
      WeddingPlanItem('accommodation.hotel', 'Hotel / Lodge Booking'),
      WeddingPlanItem('accommodation.allocation', 'Room Allocation'),
      WeddingPlanItem('accommodation.checkout', 'Checkout Coordination'),
    ],
  ),

  // ── Pooja & Rituals ───────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'pooja',
    name: 'Pooja & Rituals',
    icon: Icons.local_fire_department_outlined,
    items: [
      WeddingPlanItem('pooja.priest', 'Priest (Vadhyar) Booking'),
      WeddingPlanItem('pooja.panchangam', 'Panchangam / Muhurtham'),
      WeddingPlanItem('pooja.nichayam', 'Nichayathartham (Engagement)'),
      WeddingPlanItem('pooja.pandhakaal', 'Pandhakaal / Naandi'),
      WeddingPlanItem('pooja.sumangali', 'Sumangali Prarthanai'),
      WeddingPlanItem('pooja.kasiyathirai', 'Kaasi Yathirai Items'),
      WeddingPlanItem('pooja.mangalsnanam', 'Mangala Snanam'),
      WeddingPlanItem('pooja.kanyadaanam', 'Kanyadaanam Items'),
      WeddingPlanItem('pooja.homam', 'Homam Arrangements'),
      WeddingPlanItem('pooja.samagri', 'Pooja Samagri (Items)'),
      WeddingPlanItem('pooja.ganapathy', 'Ganapathy Pooja'),
      WeddingPlanItem('pooja.navagraha', 'Navagraha Pooja'),
      WeddingPlanItem('pooja.paalikai', 'Paalikai (Seed Pots)'),
      WeddingPlanItem('pooja.ammi', 'Ammi Midithal Items'),
      WeddingPlanItem('pooja.oonjal', 'Oonjal (Swing) Items'),
    ],
  ),

  // ── Traditional Items (Tamil-specific arrangements) ───────────────────────
  WeddingPlanCategory(
    key: 'traditional',
    name: 'Traditional Items',
    icon: Icons.temple_hindu_outlined,
    items: [
      WeddingPlanItem('traditional.seervarisai', 'Seer Varisai (Gift Exchange)'),
      WeddingPlanItem('traditional.thamboolam', 'Thamboolam Bags'),
      WeddingPlanItem('traditional.vetrilai', 'Betel Leaves & Nuts (Vetrilai Pakku)'),
      WeddingPlanItem('traditional.fruits', 'Fruits & Coconuts'),
      WeddingPlanItem('traditional.garland', 'Garlands (Maalai)'),
      WeddingPlanItem('traditional.maalaimaatral', 'Exchange Garlands (Maalai Maatral)'),
      WeddingPlanItem('traditional.madhuparkam', 'Milk & Honey (Madhuparkam)'),
      WeddingPlanItem('traditional.aarthi', 'Aarthi Plates'),
      WeddingPlanItem('traditional.kumkum', 'Kumkum & Turmeric'),
      WeddingPlanItem('traditional.kuthuvilakku', 'Kuthuvilakku (Lamps)'),
      WeddingPlanItem('traditional.thattu', 'Thattu / Plates Arrangement'),
      WeddingPlanItem('traditional.provisions', 'Paruppu Podi & Provisions'),
    ],
  ),

  // ── Return Gifts ──────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'returngifts',
    name: 'Return Gifts',
    icon: Icons.card_giftcard_outlined,
    items: [
      WeddingPlanItem('returngifts.selection', 'Return Gift Selection'),
      WeddingPlanItem('returngifts.guest', 'Guest Return Gifts'),
      WeddingPlanItem('returngifts.vip', 'VIP Return Gifts'),
      WeddingPlanItem('returngifts.silver', 'Silver Gift Items'),
      WeddingPlanItem('returngifts.sweets', 'Sweets Boxes'),
      WeddingPlanItem('returngifts.sumangali',
          'Blouse Piece / Coconut for Sumangalis'),
    ],
  ),

  // ── Reception ─────────────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'reception',
    name: 'Reception',
    icon: Icons.nightlife_outlined,
    items: [
      WeddingPlanItem('reception.planning', 'Reception Planning'),
      WeddingPlanItem('reception.stage', 'Stage Setup'),
      WeddingPlanItem('reception.invitation', 'Reception Invitation'),
      WeddingPlanItem('reception.catering', 'Reception Catering'),
      WeddingPlanItem('reception.photography', 'Reception Photography'),
      WeddingPlanItem('reception.guestflow', 'Guest Flow Plan'),
      WeddingPlanItem('reception.giftcounter', 'Gift Collection Counter'),
    ],
  ),

  // ── Registration & Legal ──────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'registration',
    name: 'Registration',
    icon: Icons.gavel_outlined,
    items: [
      WeddingPlanItem('registration.marriage', 'Marriage Registration'),
      WeddingPlanItem('registration.documents', 'Documents Preparation'),
      WeddingPlanItem('registration.witness', 'Witness Arrangement'),
      WeddingPlanItem('registration.appointment', 'Registration Appointment'),
      WeddingPlanItem('registration.ids', 'Aadhaar / ID Copies'),
      WeddingPlanItem('registration.certificate', 'Marriage Certificate Collection'),
      WeddingPlanItem('registration.notary', 'Notary / Affidavit'),
    ],
  ),

  // ── Budget & Payments ─────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'budget',
    name: 'Budget & Payments',
    icon: Icons.account_balance_wallet_outlined,
    items: [
      WeddingPlanItem('budget.total', 'Total Budget Planning'),
      WeddingPlanItem('budget.gold', 'Gold Budget'),
      WeddingPlanItem('budget.advances', 'Vendor Advance Payments'),
      WeddingPlanItem('budget.schedule', 'Balance Payment Schedule'),
      WeddingPlanItem('budget.contingency', 'Contingency Fund'),
      WeddingPlanItem('budget.tracking', 'Expense Tracking Setup'),
    ],
  ),

  // ── Security & Logistics ──────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'security',
    name: 'Security & Logistics',
    icon: Icons.security_outlined,
    items: [
      WeddingPlanItem('security.bouncer', 'Security / Bouncer Arrangement'),
      WeddingPlanItem('security.parking', 'Parking Coordinator'),
      WeddingPlanItem('security.crowd', 'Crowd Management'),
      WeddingPlanItem('security.safe', 'Gift / Jewellery Safe Custody'),
      WeddingPlanItem('security.cloakroom', 'Cloak Room'),
      WeddingPlanItem('security.lostfound', 'Lost & Found Desk'),
    ],
  ),

  // ── Emergency Planning ────────────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'emergency',
    name: 'Emergency Planning',
    icon: Icons.medical_services_outlined,
    items: [
      WeddingPlanItem('emergency.firstaid', 'First Aid Kit'),
      WeddingPlanItem('emergency.doctor', 'Doctor / Ambulance on Call'),
      WeddingPlanItem('emergency.contacts', 'Emergency Contacts List'),
      WeddingPlanItem('emergency.backupvendor', 'Backup Vendor List'),
      WeddingPlanItem('emergency.weather', 'Weather Contingency'),
      WeddingPlanItem('emergency.power', 'Power Backup Confirmation'),
      WeddingPlanItem('emergency.cash', 'Extra Cash'),
    ],
  ),

  // ── Timeline & Coordination ───────────────────────────────────────────────
  WeddingPlanCategory(
    key: 'timeline',
    name: 'Timeline',
    icon: Icons.schedule_outlined,
    items: [
      WeddingPlanItem('timeline.dayplan', 'Wedding Day Timeline'),
      WeddingPlanItem('timeline.muhurthamtime', 'Muhurtham Time Confirmation'),
      WeddingPlanItem('timeline.vendorarrival', 'Vendor Arrival Schedule'),
      WeddingPlanItem('timeline.coordinator', 'Master Coordinator Assignment'),
      WeddingPlanItem('timeline.rehearsal', 'Rehearsal'),
      WeddingPlanItem('timeline.checklist', 'Wedding Day Checklist'),
    ],
  ),
];

/// Category lookup by name (tasks store the category NAME).
WeddingPlanCategory? weddingPlanCategoryByName(String name) {
  for (final c in kWeddingPlanTemplate) {
    if (c.name == name) return c;
  }
  return null;
}

/// Icon for a task category (falls back to a generic checklist icon for
/// free-text / custom categories not in the template).
IconData weddingPlanCategoryIcon(String name) =>
    weddingPlanCategoryByName(name)?.icon ?? Icons.checklist_rtl_outlined;

/// All template category names, in canonical order (for the Tasks chips).
List<String> get kWeddingPlanCategoryNames =>
    kWeddingPlanTemplate.map((c) => c.name).toList();
