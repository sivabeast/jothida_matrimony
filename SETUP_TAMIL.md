# Jothida Matrimony — கைமுறை Setup வழிகாட்டி (தமிழ்)

இந்த ஆவணம் **code-இல் செய்ய முடியாத**, நீங்கள் Firebase Console / Google Play
Console-இல் **கைமுறையாக** செய்ய வேண்டிய வேலைகளை மட்டும் விளக்குகிறது.
Code பகுதி முழுவதும் முடிந்துவிட்டது.

ஒவ்வொரு பகுதியிலும் **எங்கே click செய்வது**, **எந்த setting-ஐ ON செய்வது**,
**எந்த file-ஐ download செய்வது**, **அதை எங்கே வைப்பது**, **எப்படி சரிபார்ப்பது**
— அனைத்தும் வரிசையாக கொடுக்கப்பட்டுள்ளது. **எந்த ஒரு step-ஐயும் விட்டுவிடாதீர்கள்.**

---

## சுருக்கம் — நீங்கள் செய்ய வேண்டியவை

| # | வேலை | ஏன் தேவை | கட்டாயமா? |
|---|------|-----------|-----------|
| 1 | ~~புதிய Logo file-ஐ project-இல் வைப்பது~~ | ஒரே logo எல்லா இடத்திலும் (§5) | **முடிந்தது** ✅ |
| 2 | Firebase → Anonymous Sign-in ஐ Enable செய்வது | Guest Mode (§6) | ஆம் |
| 3 | Firebase → Blaze Plan-க்கு Upgrade | Push Notifications (§10) | ஆம் |
| 4 | `google-services.json` download + சரியான இடத்தில் வைப்பது | FCM வேலை செய்ய | ஆம் |
| 5 | Cloud Functions Deploy | Push அனுப்ப | ஆம் |
| 6 | Firestore Rules + Indexes Deploy | புதிய rules (§9) | ஆம் |
| 7 | Play Console-இல் ஒரு build ஏற்றுவது | In-App Update (§9) | ஆம் |
| 8 | சரிபார்ப்பு (Testing) | எல்லாம் வேலை செய்கிறதா | ஆம் |

---

## 1. புதிய Logo (§5) — ✅ முடிந்துவிட்டது, நீங்கள் எதுவும் செய்ய வேண்டாம்

நீங்கள் அனுப்பிய புதிய logo (சிவப்பு பின்னணி + தங்க நிற ஜோடி + ராசி சக்கரம்)
project-இல் **ஏற்கனவே ஏற்றப்பட்டுவிட்டது**. பழைய **இரண்டு** logo-க்களும்
நீக்கப்பட்டன:

| நீக்கப்பட்ட பழைய logo | எங்கே இருந்தது |
|---|---|
| தங்க/மஞ்சள் பின்னணி logo | `assets/images/app_logo.png` |
| "Jothida Matrimony" எழுத்துடன் இருந்த logo | `branding/play_store_icon_512.png` |

இப்போது **ஒரே ஒரு** logo file மட்டும்: `assets/images/app_logo.png`.
Home screen icon, Play Store icon, Splash, Login, Drawer, App bar, Report PDF —
**எல்லாமே** இதே ஒரு file-இல் இருந்துதான் வருகிறது.

### எதிர்காலத்தில் logo-ஐ மாற்ற வேண்டுமானால்

ஒரே ஒரு command போதும் (Python + Pillow தேவை):

```bash
python tool/generate_brand_icons.py path/to/new_logo.png --write-master
```

இது தானாகவே: master file-ஐ மாற்றும் → Android-இன் 10 icon file-களையும் மீண்டும்
உருவாக்கும் → `branding/play_store_icon_512.png`-ஐயும் உருவாக்கும்.
கடைசியில் அது ஒரு நிறத்தை (colour code) print செய்யும் — அதை
`android/app/src/main/res/values/colors.xml` → `ic_launcher_background`-இல்
ஒட்டவும்.

> `dart run flutter_launcher_icons` — இனி **பயன்படுத்த வேண்டாம்**. அது logo-ஐ
> முழுமையாக விரித்து வைப்பதால், ராசி சக்கரத்தின் வெளிப்புற நட்சத்திரங்கள்
> Android-இன் icon mask-இல் வெட்டுப்பட்டுவிடும்.

### சரிபார்ப்பு

- App-ஐ phone-இல் install செய்தால் **home screen icon** புதிய logo ஆக இருக்கும்.
- Splash screen, Login page, Report PDF header — எல்லாவற்றிலும் **அதே** logo.

> **முக்கியம்:** Play Store-இல் தெரியும் icon **AAB-இல் இருந்து வராது**.
> `branding/play_store_icon_512.png`-ஐ Play Console → Store listing-இல் தனியாக
> upload செய்ய வேண்டும் (step 7).

---

## 2. Firebase → Anonymous Sign-in ஐ Enable செய்வது (§6 — Guest Mode)

App இப்போது install செய்த உடனே **Login page காட்டாது** — நேரடியாக **Home page**
திறக்கும். இதற்கு Firebase-இல் **Anonymous** login முறை ON ஆக இருக்க வேண்டும்.
(இது இல்லாவிட்டாலும் app crash ஆகாது — ஆனால் Home-இல் banners / astrology
services போன்ற தகவல்கள் காலியாகத் தெரியும்.)

### படிகள்

1. உலாவியில் திறக்கவும்: **https://console.firebase.google.com**
2. உங்கள் project-ஐ click செய்யவும் (எ.கா. `jothida-matrimony`).
3. இடது பக்க menu-வில் → **Build** → **Authentication** click செய்யவும்.
4. மேலே உள்ள **Sign-in method** tab-ஐ click செய்யவும்.
5. கீழே உள்ள providers list-இல் **Anonymous** ஐ கண்டுபிடித்து click செய்யவும்.
6. வலது மேலே உள்ள **Enable** toggle-ஐ ON (நீலம்) ஆக்கவும்.
7. **Save** button-ஐ click செய்யவும்.

### சரிபார்ப்பு

- **Anonymous** வரிசையில் Status = **Enabled** என்று பச்சை நிறத்தில் இருக்கும்.
- App-ஐ முழுவதுமாக uninstall செய்து மீண்டும் install செய்யவும் →
  **Login page வராமல் நேராக Home page** வர வேண்டும்.
- Firebase Console → **Authentication → Users** tab-இல் "Anonymous" வகை
  user ஒன்று உருவாகியிருக்கும்.

---

## 3. Firebase → Blaze Plan-க்கு Upgrade (§10 — Push Notifications)

**இதுதான் மிக முக்கியமான step.** தற்போது project **Spark (இலவச)** plan-இல்
உள்ளது. Spark plan-இல் **Cloud Functions deploy செய்ய முடியாது**. Cloud
Functions இல்லாமல் **phone-க்கு push notification வராது** (app-க்குள் உள்ள
notification list மட்டுமே வேலை செய்யும்).

> Blaze = "pay as you go". ஆனால் ஒவ்வொரு மாதமும் **இலவச அளவு (free tier)**
> உண்டு — 2 million function calls / மாதம். சிறிய app-க்கு பொதுவாக
> **₹0 கட்டணம்** வரும். இருப்பினும் card சேர்ப்பது கட்டாயம்.

### படிகள்

1. **https://console.firebase.google.com** → உங்கள் project.
2. இடது பக்க menu-வின் **கீழே** உள்ள **Upgrade** (அல்லது தற்போதைய plan பெயர்
   "Spark") என்பதை click செய்யவும்.
3. வரும் window-இல் **Blaze — Pay as you go** ஐ தேர்ந்தெடுத்து
   **Select plan** click செய்யவும்.
4. **Billing account** ஒன்றை உருவாக்கவும்:
   - **Create new billing account** → நாடு: **India** → **Continue**
   - Credit / Debit card விவரங்களை உள்ளிடவும் → **Submit and enable billing**
5. விருப்பமானது (பரிந்துரைக்கப்படுகிறது): **Set budget alert** →
   மாதம் ₹500 என வைத்து, அளவு தாண்டினால் email வரும்படி அமைக்கவும்.
6. **Purchase / Confirm** ஐ click செய்யவும்.

### சரிபார்ப்பு

- Firebase Console இடது-கீழே **Blaze** என்று காட்டும்.
- **Build → Functions** menu திறந்தால் "Upgrade required" செய்தி வராது.

---

## 4. `google-services.json` — Download + சரியான இடம்

App ஏற்கனவே ஒரு `google-services.json` உடன் வேலை செய்கிறது. ஆனால்
**Cloud Messaging (FCM) API** ஐ புதிதாக ON செய்த பிறகு, file-ஐ **மீண்டும்
download செய்து replace செய்வது** பாதுகாப்பானது.

### 4அ. Cloud Messaging API ஐ ON செய்வது

1. Firebase Console → உங்கள் project.
2. மேலே-இடதில் உள்ள **⚙️ (Settings icon)** → **Project settings**.
3. மேலே உள்ள **Cloud Messaging** tab-ஐ click செய்யவும்.
4. **Firebase Cloud Messaging API (V1)** வரிசையில் Status = **Enabled**
   என்று இருக்க வேண்டும்.
   - **Disabled** என்றால்: வலதுபுறம் உள்ள **⋮ (three dots)** → **Manage API in
     Google Cloud Console** → திறக்கும் page-இல் **Enable** button-ஐ click.

### 4ஆ. File-ஐ Download செய்வது

1. அதே **Project settings** page → முதல் tab **General**.
2. கீழே scroll செய்து **Your apps** பகுதிக்கு வரவும்.
3. Android app-ஐ (package name: **`com.jothida.jothida_matrimony`**) click.
4. **google-services.json** என்ற பொத்தானை click செய்து download செய்யவும்.

### 4இ. File-ஐ எங்கே வைப்பது

Download ஆன file-ஐ **சரியாக இந்த இடத்தில்** வைக்கவும் (பழையதை மேலெழுதவும்):

```
jothida_matrimony/android/app/google-services.json
```

> ⚠️ `android/` folder-இல் அல்ல — **`android/app/`** folder-இல்தான் வைக்க வேண்டும்.
> file பெயரை மாற்றக்கூடாது.

பிறகு:

```bash
flutter clean
```

```bash
flutter pub get
```

### சரிபார்ப்பு

- File-ஐ notepad-இல் திறந்தால் உள்ளே `"package_name":
  "com.jothida.jothida_matrimony"` இருக்க வேண்டும்.
- `"project_id"` உங்கள் Firebase project id ஆக இருக்க வேண்டும்.

---

## 5. Cloud Functions Deploy (Push அனுப்ப)

Blaze plan ஆன பிறகு மட்டுமே இது வேலை செய்யும்.

### படிகள்

1. Terminal-ஐ project folder-இல் திறக்கவும்.
2. Firebase CLI install ஆகவில்லை என்றால்:

   ```bash
   npm install -g firebase-tools
   ```

3. Login:

   ```bash
   firebase login
   ```

4. Functions-க்கான packages:

   ```bash
   npm --prefix functions install
   ```

5. Deploy:

   ```bash
   firebase deploy --only functions
   ```

6. முடிந்ததும் "Deploy complete!" என்ற செய்தி வரும்.

### சரிபார்ப்பு

```bash
firebase functions:list
```

இந்த functions **அனைத்தும்** list-இல் இருக்க வேண்டும்:

- `onNotificationCreated` — எல்லா notification-ஐயும் push ஆக அனுப்பும் (முக்கியம்)
- `onInterestWritten` — Interest Received / Accepted
- `onChatMessageCreated` — New Chat Message
- `onProfileWritten` — Profile approval
- `onAnnouncementCreated` — Admin Announcement
- `sendScheduledAnnouncements` — திட்டமிட்ட அறிவிப்புகள்
- `resetPasswordWithPhone`, `chatWithAstrologyBot`

Firebase Console → **Build → Functions** page-இலும் இவை தெரியும்.

---

## 6. Firestore Rules + Indexes Deploy

`firestore.rules` file மாற்றப்பட்டுள்ளது (§9-இல் force-update collection
நீக்கப்பட்டது). இதை deploy செய்ய வேண்டும்.

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### சரிபார்ப்பு

- Firebase Console → **Build → Firestore Database** → **Rules** tab.
- மேலே "Last deployed" நேரம் **இப்போதைய நேரமாக** இருக்க வேண்டும்.
- Rules உள்ளே `match /app_settings/{docId}` பகுதியில்
  `allow read, write: if isAdmin();` என்று இருக்க வேண்டும்.

### (விருப்பம்) பழைய Data-வை நீக்குவது

Force-update system முழுவதுமாக நீக்கப்பட்டதால், பழைய document இனி பயன்படாது:

1. Firebase Console → **Firestore Database** → **Data** tab.
2. `app_settings` collection → `app_update` document.
3. வலது மேலே **⋮** → **Delete document**.

---

## 7. Google Play Console — In-App Update (§9)

Admin panel-இல் இருந்த "App Update" page **முழுவதுமாக நீக்கப்பட்டது**.
இனி update-ஐ **Google Play தானாகவே** கையாளும். Admin எதுவும் செய்ய வேண்டாம்.

### எப்படி வேலை செய்யும்

- App திறக்கும் ஒவ்வொரு முறையும் (மற்றும் background-இல் இருந்து திரும்பும்
  போதும்) Play Store-இடம் "புதிய version உள்ளதா?" என்று கேட்கும்.
- இருந்தால் → **Immediate Update** திரை காட்டப்படும். Update செய்யாமல்
  app-ஐ பயன்படுத்த முடியாது.
- Update ஆன பிறகு → அடுத்த புதிய version வரும் வரை **மீண்டும் காட்டாது**.

### படிகள்

1. **https://play.google.com/console** → உங்கள் app.
2. **Release → Production** (அல்லது Internal testing) → **Create new release**.
3. AAB file-ஐ upload செய்யவும்.
   - `pubspec.yaml`-இல் `version: 1.4.0+8` உள்ளது. **அடுத்த release-இல்
     `+8` ஐ `+9` ஆக அதிகரிக்க வேண்டும்** (எ.கா. `version: 1.5.0+9`).
     Version code அதிகரிக்காவிட்டால் Play "update உள்ளது" என்று சொல்லாது.
4. **Store listing** page → **App icon** பகுதியில்
   `branding/play_store_icon_512.png` file-ஐ upload செய்யவும். இது **புதிய
   logo**-வுடன் ஏற்கனவே தயாராக உள்ளது (§1). பழைய, "Jothida Matrimony" எழுத்து
   இருந்த icon-ஐ இது மாற்றிவிடும் — Play Console-இல் upload செய்தால்தான் Store-இல்
   புதிய icon தெரியும்.
5. **Review release** → **Start rollout to Production**.

### சரிபார்ப்பு (மிக முக்கியம்)

> ⚠️ In-App Update-ஐ **computer-இல் இருந்து நேரடியாக install செய்த
> APK-இல் சோதிக்க முடியாது**. Google Play-இல் இருந்து install செய்த
> build-இல் மட்டுமே வேலை செய்யும். இது Play-இன் விதி — code பிழை அல்ல.

சோதிக்கும் முறை:

1. Play Console → **Testing → Internal testing** → version code `8` உடன் ஒரு
   build ஏற்றவும்.
2. அதை உங்கள் phone-இல் **Play Store link மூலம்** install செய்யவும்.
3. பிறகு version code `9` உடன் இன்னொரு build ஏற்றவும்.
4. Phone-இல் app-ஐ திறக்கவும் → **Update திரை** தானாக வர வேண்டும்.

---

## 8. இறுதி சரிபார்ப்பு பட்டியல் (Testing Checklist)

App-ஐ phone-இல் install செய்து இவற்றை ஒவ்வொன்றாக சோதிக்கவும்:

### Guest Mode (§6)

- [ ] App-ஐ முதன்முறை திறந்தால் **Login page வராமல்** Home page வருகிறது.
- [ ] Home-இல் banners, memberships, astrology services தெரிகின்றன.
- [ ] **Matches / Interests / Reports** tab-ஐ தொட்டால் Login திரை வருகிறது.
- [ ] ஒரு Profile-ஐ திறக்க முயன்றால் இந்த தமிழ் செய்தி வருகிறது:
      *"மற்ற உறுப்பினர்களின் Profile-களை பார்க்க, முதலில் உங்கள் Matrimony
      Profile-ஐ உருவாக்குங்கள்."*

### Astrology Appointment (§8)

- [ ] Login மட்டும் செய்தால் (Matrimony Profile இல்லாமல்) appointment book
      செய்ய முடிகிறது.
- [ ] Confirm-க்கு முன் **Name / Mobile Number / Date of Birth** கேட்கிறது.
- [ ] Google login-இல் phone number இல்லாவிட்டால், அது காலியாக வந்து
      நீங்கள் நிரப்ப முடிகிறது.

### Requests vs Appointments (§2 / §3 / §4)

- [ ] Admin → **Requests** page-இல் **Pending / Completed** என இரண்டு tab.
- [ ] Requests page-இல் **appointment booking எதுவும் தெரியவில்லை**.
- [ ] ஒரு request card-ஐ திறந்தால் Groom Details, Bride Details, Horoscope
      Details, **Fill Report** button தெரிகிறது.
- [ ] Employee portal-இலும் அதே Pending / Completed அமைப்பு.
- [ ] Appointment bookings **Admin → Appointments** page-இல் மட்டும் தெரிகிறது.

### Compatibility Report (§1)

- [ ] **திசா சந்தி** மற்றும் **நடப்பு திசாபுத்தி** — text box இல்லை.
- [ ] சர்ப்ப தோஷம் போலவே ✓ (உண்டு) / ✗ (இல்லை) பொத்தான்கள் மட்டும்.
- [ ] தேர்வு செய்யாமல் Submit செய்தால் எச்சரிக்கை வருகிறது.

### Push Notifications (§10)

*(Cloud Functions deploy ஆன பிறகு மட்டும்)*

- [ ] App **திறந்திருக்கும் போது** notification வருகிறது.
- [ ] App **background-இல்** இருக்கும் போது வருகிறது.
- [ ] App **முழுவதுமாக மூடியிருக்கும்** போது வருகிறது.
- [ ] **Lock screen**-இல் தெரிகிறது.
- [ ] Notification-ஐ தொட்டால் **சம்பந்தப்பட்ட page** நேரடியாக திறக்கிறது.
- [ ] Notification page-ஐ திறந்தவுடன் **சிவப்பு badge எண் 0 ஆகிறது**.

விரைவாக சோதிக்க: இரண்டு phone-களில் இரண்டு account-கள் → ஒன்றில் இருந்து
மற்றொன்றுக்கு **Interest அனுப்பவும்**. மற்ற phone-இல் push வர வேண்டும்.

### Muhurtham Card (§12)

- [ ] Home page-இல் **"Marriage Muhurtham Calendar"** முழு தலைப்பு தெரிகிறது.
- [ ] எங்கும் **"..."** (truncation) இல்லை.
- [ ] Card நடுவில் **பெரிய "Coming Soon"** தெரிகிறது.

---

## பிரச்சனை வந்தால் (Troubleshooting)

| அறிகுறி | காரணம் | தீர்வு |
|---------|--------|--------|
| Push notification வரவே இல்லை | Functions deploy ஆகவில்லை | Step 3 → Step 5 |
| `firebase deploy` — "Blaze required" பிழை | Spark plan-இல் உள்ளது | Step 3 |
| App திறந்தால் Login page வருகிறது | Anonymous sign-in OFF | Step 2 |
| Home-இல் banners காலியாக உள்ளது | Anonymous sign-in OFF | Step 2 |
| Icon மாறவில்லை | Launcher icons regenerate ஆகவில்லை | Step 1 → command 2 |
| Play Store-இல் பழைய icon | Store listing-இல் upload ஆகவில்லை | Step 7 → 4 |
| In-App Update வரவில்லை | Play-இல் இருந்து install செய்யவில்லை | Step 7 சரிபார்ப்பு |
| `permission-denied` பிழை | Rules deploy ஆகவில்லை | Step 6 |

---

## குறிப்பு — Membership Notifications

இந்த app-இல் தற்போது **subscription / paid membership system இல்லை** —
matrimony வசதிகள் அனைத்தும் இலவசம். ஆகவே "Membership Activated" /
"Membership Expired" notification-களை **Admin கைமுறையாக அனுப்பும்படி**
அமைக்கப்பட்டுள்ளது:

**Admin → Users → (ஒரு user-ஐ தேர்வு) → View Details** → கீழே உள்ள
**Membership Activated** / **Membership Expired** பொத்தான்கள்.

எதிர்காலத்தில் billing system சேர்க்கும்போது, அதே
`AppNotificationEvent.membershipActivated` / `.membershipExpired` event-களை
நேரடியாக அழைத்தால் போதும் — push pipeline ஏற்கனவே தயாராக உள்ளது.
