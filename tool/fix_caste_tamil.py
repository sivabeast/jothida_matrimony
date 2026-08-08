#!/usr/bin/env python3
"""Rebuild the Tamil names for Religion → Caste → Sub-caste master data (§10).

Every one of the 541 sub-castes shipped with `nameTamilAuto: true` — a machine
transliteration that mangles the community names people actually use:

    Kulalar            -> குலலர்      (should be குலாலர்)
    Adi Dravida        -> அதி ட்ரவித   (should be ஆதி திராவிடா)
    Agamudaya Mudaliar -> அகமுதய முதலிஅர் (should be அகமுடைய முதலியார்)

The errors are systematic — dropped long vowels, த for ட, no gemination, an
`-ar` suffix rendered அர் instead of ார் — so this fixes the VOCABULARY rather
than the 541 strings. Names are rebuilt word by word from a curated lexicon of
the terms that actually occur; anything the lexicon does not cover falls back
to a transliterator and keeps `nameTamilAuto: true`, so what is still
machine-made stays honestly labelled instead of silently looking authoritative.

It also attaches search `aliases` (§9) for the spellings people type.

Run:  python tool/fix_caste_tamil.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "master_data")

# ── Whole-name overrides: idioms that do not translate word by word ──────────
PHRASES = {
    "no caste bar": "சாதி வேறுபாடு இல்லை",
    "no sub caste": "உட்பிரிவு இல்லை",
    "other": "மற்றவை",
    "others": "மற்றவை",
    "inter religion": "மத வேறுபாடு இல்லை",
    "inter caste": "சாதி வேறுபாடு இல்லை",
    "church of south india": "தென்னிந்திய திருச்சபை",
    "church of north india": "வடஇந்திய திருச்சபை",
    "assembly of god": "அசெம்பிளி ஆஃப் காட்",
    "seventh day adventist": "ஏழாம் நாள் அட்வென்டிஸ்ட்",
    "born again": "மறுபிறப்பு கிறிஸ்தவர்",
    "salvation army": "இரட்சண்ய சேனை",
    "spiritual but not religious": "ஆன்மீகம் — மதம் சாராதவர்",
}

# ── Word lexicon: the real Tamil for each term that occurs in the data ───────
WORDS = {
    # Generic / structural
    "other": "மற்றவை", "others": "மற்றவை", "no": "இல்லை", "caste": "சாதி",
    "bar": "வேறுபாடு", "sub": "உட்", "inter": "இடை", "religion": "மதம்",
    "of": "", "and": "மற்றும்", "not": "அல்ல", "but": "ஆனால்",
    # Regions / languages
    "tamil": "தமிழ்", "telugu": "தெலுங்கு", "kannada": "கன்னட",
    "malayalam": "மலையாள", "gujarati": "குஜராத்தி", "marathi": "மராத்தி",
    "hindu": "இந்து", "andhra": "ஆந்திர", "north": "வட", "south": "தென்",
    "india": "இந்தியா", "malabar": "மலபார்", "kongu": "கொங்கு",
    "nanjil": "நாஞ்சில்", "pandya": "பாண்டிய", "thanjavur": "தஞ்சாவூர்",
    "arcot": "ஆற்காடு", "sembanad": "செம்பநாடு", "ganjam": "கஞ்சம்",
    "thondaimandala": "தொண்டைமண்டல", "nattu": "நாட்டு", "nattukottai": "நாட்டுக்கோட்டை",
    "karaikattu": "காரைக்காட்டு", "arunattu": "அறுநாட்டு", "esanattu": "ஈசநாட்டு",
    "easanattu": "ஈசநாட்டு", "periya": "பெரிய", "suriyur": "சூரியூர்",
    "acharapakkam": "ஆச்சாரப்பாக்கம்", "elur": "ஏலூர்", "kondaiyankottai": "கொண்டையங்கோட்டை",
    "gandarvakottai": "கந்தர்வக்கோட்டை", "kootappal": "கூட்டப்பால்",
    "piramalai": "பிரமலை", "manjaputhur": "மஞ்சபுத்தூர்", "pudukkadai": "புதுக்கடை",
    "nattathi": "நாட்டாத்தி", "mel": "மேல்", "vada": "வட",
    # Core Tamil communities
    "vellalar": "வேளாளர்", "vellala": "வேளாள", "vellalan": "வேளாளன்",
    "vellan": "வெள்ளான்", "chettiar": "செட்டியார்", "setti": "செட்டி",
    "gounder": "கவுண்டர்", "gowda": "கவுடா", "wodeya": "வொடேய",
    "naidu": "நாயுடு", "mudaliar": "முதலியார்", "mudaliyar": "முதலியார்",
    "nadar": "நாடார்", "kallar": "கள்ளர்", "naicker": "நாயக்கர்",
    "naika": "நாயக்கா", "pillai": "பிள்ளை", "maravar": "மறவர்",
    "saiva": "சைவ", "veerasaiva": "வீரசைவ", "adi": "ஆதி",
    "dravida": "திராவிடா", "sozhia": "சோழிய", "reddy": "ரெட்டி",
    "reddiar": "ரெட்டியார்", "balija": "பலிஜ", "brahmin": "பிராமணர்",
    "lingayat": "லிங்காயத்", "agamudayar": "அகமுடையார்", "agamudaya": "அகமுடைய",
    "ambalakarar": "அம்பலக்காரர்", "ambalakaran": "அம்பலக்காரன்",
    "devanga": "தேவாங்க", "dhevanga": "தேவாங்க", "kula": "குல",
    "kulam": "குலம்", "kshatriya": "க்ஷத்திரிய", "vettuva": "வேட்டுவ",
    "kamma": "கம்ம", "kammavar": "கம்மவார்", "karuneegar": "கருணீகர்",
    "konar": "கோனார்", "yadava": "யாதவ", "golla": "கொல்ல",
    "moopanar": "மூப்பனார்", "mooppanar": "மூப்பனார்", "udayar": "உடையார்",
    "servai": "சேர்வை", "badaga": "படக", "bestha": "பெஸ்த", "besta": "பெஸ்த",
    "vanniya": "வன்னிய", "vanniyar": "வன்னியர்", "kurumba": "குறும்ப",
    "gramani": "கிராமணி", "isai": "இசை", "jangam": "ஜங்கம்",
    "senguntha": "செங்குந்த", "sengunthar": "செங்குந்தர்", "raju": "ராஜு",
    "razu": "ராஜு", "meenavar": "மீனவர்", "pandaram": "பண்டாரம்",
    "pandaaram": "பண்டாரம்", "saliyar": "சாலியர்", "sali": "சாலி",
    "sale": "சாலே", "padmasaliyar": "பத்மசாலியர்", "sourashtra": "சௌராஷ்டிர",
    "paraiyar": "பறையர்", "sambavar": "சாம்பவர்", "valluvan": "வள்ளுவன்",
    "pallan": "பள்ளன்", "pallar": "பள்ளர்", "thuluva": "துளுவ", "tuluva": "துளுவ",
    "rajakula": "ராஜகுல", "rajakulam": "ராஜகுலம்",
    "parvatharajakulam": "பர்வதராஜகுலம்", "parvatha": "பர்வத",
    "maniyakaarar": "மணியக்காரர்", "arunthathiyar": "அருந்ததியர்",
    "chakkiliyan": "சக்கிலியன்", "madari": "மாதாரி", "madiga": "மாதிக",
    "pagadai": "பகடை", "thoti": "தோட்டி", "komati": "கோமட்டி",
    "vaisya": "வைசிய", "vysya": "வைசிய", "aryavysya": "ஆரிய வைசிய",
    "gavara": "கவர", "gajula": "கஜுல", "kavarai": "கவரை",
    "boya": "பொய", "boyar": "பொயர்", "boyer": "பொயர்",
    "bhandari": "பண்டாரி", "bandari": "பண்டாரி",
    "pattinavar": "பட்டினவர்", "gandla": "கந்தல",
    "senaikudaiyar": "சேனைக்குடையார்", "senaithalaivar": "சேனைத்தலைவர்",
    "urali": "ஊராளி", "kaikolar": "கைக்கோளர்", "idaiyar": "இடையர்",
    "ayar": "ஆயர்", "koteyar": "கோட்டேயர்", "kotegara": "கோட்டேகார",
    "rajaka": "ரஜக", "vamsam": "வம்சம்", "kulalar": "குலாலர்",
    "kuruba": "குறுப", "mukkuvar": "முக்குவர்", "nattaman": "நாட்டாமான்",
    "malayaman": "மலையமான்", "karkathar": "கார்காத்தார்",
    "mukkulathor": "முக்குலத்தோர்", "mutharaiyar": "முத்தரையர்",
    "muthuraiyar": "முத்துராயர்", "muthuraja": "முத்துராஜா",
    "mutracha": "முத்ராச", "thuraiyar": "துரையர்", "kapu": "காபு",
    "nair": "நாயர்", "pandithar": "பண்டிதர்", "palli": "பள்ளி",
    "pakanati": "பாகநாடு", "vannar": "வண்ணார்", "kammalar": "கம்மாளர்",
    "yogeeswarar": "யோகீஸ்வரர்", "thevar": "தேவர்", "iyer": "ஐயர்",
    "iyengar": "ஐயங்கார்", "vadakalai": "வடகலை", "thenkalai": "தென்கலை",
    "gurukkal": "குருக்கள்", "smartha": "ஸ்மார்த்த", "madhwa": "மாத்வ",
    "vadama": "வடமா", "brahacharanam": "பிரகச்சரணம்", "vathima": "வாத்திமா",
    "ashtasahasram": "அஷ்டசகஸ்ரம்", "mukkani": "முக்காணி", "sri": "ஸ்ரீ",
    "vaishnava": "வைஷ்ணவ", "sankethi": "சங்கேதி", "deshastha": "தேசஸ்த",
    "niyogi": "நியோகி", "vaidiki": "வைதிகி", "saraswat": "சரஸ்வத்",
    "havyaka": "ஹவ்யக", "embranthiri": "எம்பிராந்திரி", "nambudiri": "நம்பூதிரி",
    "goswami": "கோஸ்வாமி", "anavil": "அனாவில்", "nagarathar": "நகரத்தார்",
    "vaniya": "வாணிய", "beri": "பேரி", "kasukara": "காசுக்கார",
    "kasukkara": "காசுக்கார", "pannirandam": "பன்னிரண்டாம்",
    "ayira": "ஆயிர", "manai": "மனை", "karpoora": "கற்பூர",
    "devendrakulathan": "தேவேந்திரகுலத்தான்", "devendra": "தேவேந்திர",
    "kudumban": "குடும்பன்", "kadaiyan": "கடையன்", "kaladi": "களடி",
    "pannadi": "பன்னாடி", "vathiriyan": "வாத்திரியன்", "sedar": "சேடர்",
    "settukkarar": "செட்டுக்காரர்", "anuppa": "அனுப்ப",
    "padaithalai": "படைத்தலை", "sanku": "சங்கு", "pala": "பால",
    "poosari": "பூசாரி", "vokkaliga": "வொக்கலிக", "sanar": "சாணார்",
    "shanar": "சாணார்", "melakkarar": "மேளக்காரர்", "nattuvar": "நட்டுவர்",
    "thavil": "தவில்", "nagaswaram": "நாகஸ்வரம்", "choudary": "சௌத்ரி",
    "kannadiyan": "கன்னடியன்", "saineegar": "சைநீகர்",
    "dasapalanji": "தசபளஞ்சி", "kanakkar": "கணக்கர்", "kaikkattu": "கைக்காட்டு",
    "krishnan": "கிருஷ்ணன்", "vagaiyara": "வகையற", "surya": "சூர்ய",
    "kuyavar": "குயவர்", "velar": "வேளார்", "odde": "ஒட்டே",
    "oddar": "ஒட்டர்", "kummara": "கும்மார", "kusavan": "குசவன்",
    "kuravan": "குறவன்", "kurava": "குறவ", "koravar": "கொறவர்",
    "narikuravar": "நரிக்குறவர்", "sidhanar": "சிதனார்",
    "halumatha": "ஹாலுமத", "pal": "பால்", "sembadavar": "செம்படவர்",
    "karaiyar": "கரையார்", "nulayar": "நுளையர்", "mogaveera": "மொகவீர",
    "paravar": "பரவர்", "santror": "சான்றோர்", "karukku": "கருக்கு",
    "pattayam": "பட்டயம்", "vaduga": "வடுக", "tottiya": "தொட்டிய",
    "tottiyan": "தொட்டியன்", "palayakkara": "பாளையக்கார", "velama": "வேலம",
    "telaga": "தெலக", "ediga": "எடிக", "munnuru": "முன்னூறு",
    "perika": "பெரிக", "menon": "மேனோன்", "kurup": "குருப்",
    "nambiar": "நம்பியார்", "kartha": "கர்த்தா", "karkartha": "கர்க்கர்த்தா",
    "andi": "ஆண்டி", "vaidyar": "வைத்தியர்", "navithar": "நாவிதர்",
    "ambattar": "அம்பட்டர்", "surutiman": "சுருதிமான்", "kodikal": "கொடிக்கால்",
    "illaththu": "இல்லத்து", "motati": "மோட்டாடி", "velnati": "வேல்நாடு",
    "desuru": "தேசூரு", "desai": "தேசாய்", "pattariyar": "பட்டறியார்",
    "siviar": "சிவியார்", "gangaputra": "கங்காபுத்ர", "nayee": "நாயீ",
    "pronopokari": "பிரணோபகாரி", "vaisha": "வைசிய", "khatri": "கத்ரி",
    "arora": "அரோரா", "jat": "ஜாட்", "ramgarhia": "ராம்கரியா",
    "ahluwalia": "அலுவாலியா", "saini": "சைனி", "mazhabi": "மஸ்ஹபி",
    "bania": "பனியா", "marwari": "மார்வாரி", "oswal": "ஓஸ்வால்",
    "digambar": "திகம்பர்", "svetambar": "ஸ்வேதாம்பர்",
    # Faiths
    "christian": "கிறிஸ்தவர்", "catholic": "கத்தோலிக்கர்",
    "protestant": "புராட்டஸ்டன்ட்", "pentecostal": "பெந்தேகோஸ்தே",
    "jacobite": "யாக்கோபாய", "orthodox": "ஆர்த்தடாக்ஸ்", "syro": "சிரோ",
    "knanaya": "கனானய", "syrian": "சிரிய", "church": "திருச்சபை",
    "baptist": "பாப்டிஸ்ட்", "evangelical": "சுவிசேஷ",
    "adventist": "அட்வென்டிஸ்ட்", "malankara": "மலங்கரை",
    "marthoma": "மார்த்தோமா", "salvation": "இரட்சண்ய", "army": "சேனை",
    "roman": "ரோமன்", "god": "கடவுள்", "seventh": "ஏழாம்", "day": "நாள்",
    "born": "பிறந்த", "again": "மீண்டும்", "assembly": "சபை",
    "muslim": "முஸ்லிம்", "sunni": "சுன்னி", "shia": "ஷியா",
    "hanafi": "ஹனஃபி", "shafi": "ஷாஃபி", "bohra": "போரா",
    "sheikh": "ஷேக்", "syed": "சையது", "pathan": "பதான்",
    "mughal": "முகலாய", "marakayar": "மரைக்காயர்", "rowther": "ராவுத்தர்",
    "kayalar": "கயலார்", "dudekula": "துடேகுல", "ansari": "அன்சாரி",
    "mappila": "மாப்பிள்ளை", "dekkani": "தக்காணி", "memon": "மேமன்",
    "labbai": "லப்பை", "sikh": "சீக்கியர்", "jain": "சமணர்",
    "buddhist": "பௌத்தர்", "navayana": "நவயான", "theravada": "தேரவாத",
    "mahayana": "மகாயான", "parsi": "பார்சி", "irani": "ஈரானி",
    "brahmo": "பிரம்ம", "spiritual": "ஆன்மீக", "samaj": "சமாஜ்",
    # Remaining Tamil community terms
    "dravidar": "திராவிடர்", "arya": "ஆரிய", "devandra": "தேவேந்திர",
    "kannadiyar": "கன்னடியர்", "kuravar": "குறவர்", "kurumbar": "குறும்பர்",
    "parkavakulam": "பற்கவகுலம்", "vishwakarma": "விஸ்வகர்மா",
    "viswakarma": "விஸ்வகர்மா", "vishwabrahmin": "விஸ்வபிராமணர்",
    "illaivaniar": "இளைவாணியர்", "anuppan": "அனுப்பன்",
    "patnulkaran": "பட்டுநூல்காரன்", "pattunoolkarar": "பட்டுநூல்காரர்",
    "saurashtra": "சௌராஷ்டிர", "gangai": "கங்கை", "ekali": "ஏகாலி",
    "salavai": "சலவை", "thozhilalar": "தொழிலாளர்", "puthirai": "புதிரை",
    "vannan": "வண்ணான்", "dhobi": "சலவைத் தொழிலாளி",
    "kshatriyar": "க்ஷத்திரியர்", "padayachi": "படையாச்சி",
    "agnikula": "அக்னிகுல", "vanniar": "வன்னியர்", "sirukudi": "சிறுகுடி",
    "panneeru": "பன்னீரு", "chozhia": "சோழிய", "vettuvar": "வேட்டுவர்",
    "achari": "ஆசாரி", "asari": "ஆசாரி", "ashari": "ஆசாரி",
    "kannar": "கன்னார்", "kollar": "கொல்லர்", "thattar": "தட்டார்",
    "thatchar": "தச்சர்", "sirpi": "சிற்பி", "pancha": "பஞ்ச",
    "asthathra": "அஸ்தத்ர", "yogi": "யோகி", "jogi": "ஜோகி",
    "yogeeswara": "யோகீஸ்வர", "banajiga": "பனஜிக", "sadar": "சாதர்",
    "dalit": "தலித்", "bharathar": "பரதர்", "fernando": "பெர்னாண்டோ",
    "nainar": "நயினார்", "vania": "வாணிய", "vaishya": "வைசிய",
    "kalal": "கலால்", "sarak": "சரக்", "ramgharia": "ராம்கரியா",
    "majhabi": "மஸ்ஹபி", "ramdasia": "ராம்தாசியா", "marwadi": "மார்வாடி",
    # Muslim community variants
    "ithna": "இஸ்னா", "ismaili": "இஸ்மாயிலி", "dawoodi": "தாவூதி",
    "shaik": "ஷேக்", "sayyad": "சையது", "sayyid": "சையது",
    "khan": "கான்", "pashtun": "பஷ்தூன்", "mogal": "முகலாய",
    "lebbai": "லப்பை", "labba": "லப்பை", "marakkayar": "மரைக்காயர்",
    "maraikkayar": "மரைக்காயர்", "marakkar": "மரைக்கார்",
    "ravuthar": "ராவுத்தர்", "rawther": "ராவுத்தர்", "ravuther": "ராவுத்தர்",
    "kayal": "கயல்", "kayalan": "கயலான்", "pinjari": "பிஞ்சாரி",
    "laddaf": "லத்தாஃப்", "julaha": "ஜுலாஹா", "momin": "மோமின்",
    "mapilla": "மாப்பிள்ளை", "moplah": "மாப்பிள்ளை", "kutchi": "கச்சி",
    "deccani": "தக்காணி", "urdu": "உருது",
    # Christian denominations
    "latin": "லத்தீன்", "rc": "ரோமன் கத்தோலிக்க", "csi": "தென்னிந்திய திருச்சபை",
    "anglican": "ஆங்கிலிக்கன்", "lutheran": "லூத்தரன்",
    "methodist": "மெதடிஸ்ட்", "reformed": "சீர்திருத்த",
    "presbyterian": "பிரஸ்பிட்டீரியன்", "the": "", "mission": "மிஷன்",
    "indian": "இந்திய", "charismatic": "கரிஸ்மாட்டிக்", "non": "அல்லாத",
    "denominational": "பிரிவுசாரா", "brethren": "சகோதரத்துவ",
    "mar": "மார்", "thoma": "தோமா",
    # Jain / Buddhist / other
    "digambara": "திகம்பர", "shwetambar": "ஸ்வேதாம்பர்",
    "swetambar": "ஸ்வேதாம்பர்", "samanar": "சமணர்", "osval": "ஓஸ்வால்",
    "neo": "நவ", "ambedkarite": "அம்பேத்கரிய", "hinayana": "ஹீனயான",
    "zoroastrian": "ஜொராஸ்ட்ரிய", "believer": "நம்பிக்கையாளர்",
    "in": "", "atheist": "நாத்திகர்", "agnostic": "அஞ்ஞேயவாதி",
}

# ── Fallback transliteration, only for words the lexicon misses ─────────────
# Longest-match-first so multi-letter clusters win over single letters.
TRANSLIT = [
    ("aa", "ஆ"), ("ai", "ai"), ("au", "ஔ"), ("ee", "ஈ"), ("oo", "ஊ"),
    ("kh", "க"), ("gh", "க"), ("ch", "ச"), ("sh", "ஷ"), ("th", "த"),
    ("dh", "த"), ("ph", "ப"), ("bh", "ப"), ("zh", "ழ"), ("ng", "ங"),
    ("ny", "ஞ"),
]
CONS = {
    "k": "க", "g": "க", "c": "ச", "j": "ஜ", "t": "ட", "d": "ட",
    "n": "ன", "p": "ப", "b": "ப", "m": "ம", "y": "ய", "r": "ர",
    "l": "ல", "v": "வ", "w": "வ", "s": "ச", "h": "ஹ", "f": "ஃப",
    "z": "ஸ", "x": "க்ஸ", "q": "க",
}
VOWEL_SIGN = {"a": "", "i": "ி", "u": "ு", "e": "ெ", "o": "ொ"}
VOWEL_INDEP = {"a": "அ", "i": "இ", "u": "உ", "e": "எ", "o": "ஒ"}


def translit(word):
    """Crude Latin→Tamil for a word the lexicon does not know."""
    w = word.lower()
    out, i, prev_cons = [], 0, False
    while i < len(w):
        for src, dst in TRANSLIT:
            if w.startswith(src, i):
                if src == "ai":
                    out.append("ை" if prev_cons else "ஐ")
                elif dst in ("ஆ", "ஈ", "ஊ", "ஔ"):
                    sign = {"ஆ": "ா", "ஈ": "ீ", "ஊ": "ூ", "ஔ": "ௌ"}[dst]
                    out.append(sign if prev_cons else dst)
                else:
                    if prev_cons:
                        out.append("்")
                    out.append(dst)
                    prev_cons = True
                    i += len(src)
                    break
                prev_cons = False
                i += len(src)
                break
        else:
            c = w[i]
            if c in CONS:
                if prev_cons:
                    out.append("்")
                out.append(CONS[c])
                prev_cons = True
            elif c in VOWEL_SIGN:
                out.append(VOWEL_SIGN[c] if prev_cons else VOWEL_INDEP[c])
                prev_cons = False
            i += 1
    if prev_cons:
        out.append("்")
    return "".join(out)


def tamil_for(name):
    """(tamil, fully_curated) for an English caste / sub-caste name."""
    key = re.sub(r"[^a-z0-9 ]+", " ", name.lower())
    key = re.sub(r"\s+", " ", key).strip()
    if key in PHRASES:
        return PHRASES[key], True

    parts, curated = [], True
    for token in key.split():
        if token in WORDS:
            if WORDS[token]:
                parts.append(WORDS[token])
        elif token.isdigit():
            parts.append(token)
        else:
            parts.append(translit(token))
            curated = False
    return " ".join(p for p in parts if p).strip(), curated


def aliases_for(name):
    """Spellings people type: the no-space form and common th/t, v/w swaps."""
    lower = name.lower()
    out = {lower.replace(" ", ""), lower.replace("-", " ")}
    for a, b in (("th", "t"), ("dh", "d"), ("ee", "i"), ("oo", "u")):
        if a in lower:
            out.add(lower.replace(a, b))
    out.discard(lower)
    return sorted(a for a in out if a and a != lower)


def process(filename, name_key="name"):
    path = os.path.join(DATA, filename)
    with open(path, encoding="utf-8") as fh:
        rows = json.load(fh)

    curated_n = auto_n = changed = 0
    for row in rows:
        tamil, curated = tamil_for(row[name_key])
        if row.get("nameTamil") != tamil:
            changed += 1
        row["nameTamil"] = tamil
        # Only what the fallback produced stays flagged as machine-made.
        if curated:
            row.pop("nameTamilAuto", None)
            curated_n += 1
        else:
            row["nameTamilAuto"] = True
            auto_n += 1
        al = aliases_for(row[name_key])
        if al:
            row["aliases"] = al
        else:
            row.pop("aliases", None)

    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"  {filename}: {len(rows)} rows, {changed} Tamil names rewritten, "
          f"{curated_n} curated, {auto_n} still transliterated")
    return [r[name_key] for r in rows if r.get("nameTamilAuto")]


def main():
    print("Rebuilding Tamil names for the community master data…")
    leftovers = []
    for f in ("master_religions.json", "master_castes.json",
              "master_subcastes.json"):
        leftovers += process(f)
    if leftovers:
        print(f"\n{len(leftovers)} names still fall back to transliteration "
              "(flagged nameTamilAuto). Add them to WORDS to curate:")
        for n in leftovers[:40]:
            print(f"    {n}")
        if len(leftovers) > 40:
            print(f"    … and {len(leftovers) - 40} more")
    else:
        print("\nEvery name is curated — no machine transliteration left.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
