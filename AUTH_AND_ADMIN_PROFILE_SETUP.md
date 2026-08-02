# Authentication & Admin Profile Creation — setup

Everything in this document is about **deployment**, not code. The app builds and
runs as-is; these two steps switch on the parts that need backend configuration.

---

## 1. Deploy the Firestore rules (REQUIRED)

A new collection, `login_index`, was added. Without its rule, **login with a
mobile number cannot resolve accounts that registered with a real e-mail**, and
account creation cannot write its index entry.

```bash
firebase deploy --only firestore:rules
```

### What `login_index` is

`login_index/{10-digit-mobile}` → `{ authEmail, uid, updatedAt }`

Firebase Authentication verifies a password against an **e-mail** credential
only. A member signing in with their **mobile number** therefore has to be
resolved to that address *before* they are authenticated — which is why the read
is public. The document holds nothing but the sign-in address and its owner: no
profile, contact or account data is duplicated. `users/{uid}` remains the single
source of truth for the account itself.

Writes are locked to the owner (`uid == request.auth.uid`), so nobody can
re-point another member's number at their own account.

### Accounts with no e-mail

A member created by an admin often has no e-mail. Their Firebase credential then
uses a deterministic, **non-deliverable** address derived from their number:

```
p<10-digit-mobile>@phone.jothidamatrimony.app
```

Nothing is ever sent to it — it only carries the password credential — and phone
login resolves it without any lookup at all.

---

## 2. Deploy the OTP password-reset function (OPTIONAL)

"Forgot Password → **Email**" works with no backend at all (Firebase sends the
reset link).

"Forgot Password → **Mobile Number**" needs one callable function, because the
client SDK can only change the password of the account it is signed into, and
verifying an SMS code signs the device into the *phone-provider* identity rather
than the member's password account.

```bash
firebase deploy --only functions:resetPasswordWithPhone
```

The function (`functions/index.js`) refuses anything it cannot prove:

1. the caller must hold an OTP-verified phone session
   (`sign_in_provider == 'phone'`);
2. the verified number must equal the number being reset;
3. it resolves that number to the owner through `login_index` and sets the
   password with the Admin SDK;
4. it deletes the throwaway phone identity, so OTP resets never litter Firebase
   Auth with orphan accounts.

Until it is deployed the app says so plainly on that screen and points the member
at the e-mail path — it never fails silently.

**Prerequisite:** Phone sign-in must be enabled in *Firebase Console →
Authentication → Sign-in method*, and the app's SHA-1/SHA-256 registered (the
same requirement Google Sign-In already has).

---

## 3. Admin "Create Matrimony Profile"

*Admin → Settings → Create Matrimony Profile* (`/admin/create-profile`).

It runs the **same** profile-creation wizard members use — same fields, same
validation, same document shape — and appends one final **Login Credentials**
step (mobile + e-mail pre-filled from the Contact step, both editable).

On save:

1. the member's Firebase Auth account is created on a **secondary Firebase app**
   so the admin's own session is never swapped out;
2. `users/{uid}` and the `login_index` entry are written from that new member's
   session, so no security rule has to be loosened for the admin;
3. the profile and contact records are written by the admin under the existing
   admin rules;
4. the account is flagged `isProfileComplete: true` — an admin-created member is
   **never** asked to create a profile they already have;
5. a **Share Login Details** dialog opens WhatsApp with a ready-made message
   containing the login details, the Play Store link and sign-in instructions.

Duplicates are impossible: the mobile number is checked against `login_index`
before anything is created, and a duplicate e-mail is rejected by Firebase
itself.

The Play Store link in that message uses the URL configured in *Admin → Settings
→ App Update Settings* when one is set; otherwise it falls back to the listing
for `com.jothida.jothida_matrimony`.

---

## 4. App Check

App Check enforcement (if on) applies to the secondary Firebase app too, so it is
activated for that instance as well. Nothing extra to configure — the same
registration that lets the main app sign in covers it.
