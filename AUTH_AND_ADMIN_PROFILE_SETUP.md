# Authentication, accounts & admin login management — setup

How logins, matrimony profiles and password recovery fit together, and what has
to be deployed or configured for each part.

---

## 0. Account policy

| Rule | Enforced by |
|---|---|
| **One mobile number → one login account** | `login_index/{mobile}` — a create-only registry claimed atomically at registration and admin provisioning (`LoginDirectoryService.claim`); rules refuse a claim for anyone but the caller (or an admin) |
| **One login (Firebase UID) → at most one matrimony profile** | `profile_owners/{uid}.profileId` — written in a transaction before the profile; the rules refuse any profile create whose id does not match it |
| The **UID**, never the phone number, links a login to its profile | `profiles.userId`; owners cannot change it (rules) |
| Logins and profiles are separate | A second login identity is never turned into a second profile. Account Health lists it; the admin links or removes it explicitly — nothing is merged automatically |
| Admin rights come from `users/{uid}.role`, which a member **cannot** raise | Role guard in `firestore.rules` (`allowedSelfRole`) + every admin Cloud Function re-reads the role server-side |

The app's password logins are Firebase **e-mail/password** credentials. A member
without a real e-mail uses the non-deliverable address
`p<10-digit-mobile>@phone.jothidamatrimony.app`; `login_index` maps a mobile
number to whichever address the account uses.

---

## 1. Why "An account already exists with this phone number" appeared after the login was deleted

Two independent leftovers:

1. **Admin → Delete User** removed `profiles` and `users/{uid}` only. The
   `login_index/{mobile}` entry survived, and that entry is exactly what the
   Create Profile → Login Credentials step checked → *"This mobile number
   already has an account."*
2. The **Firebase Authentication record** survived too — a client app cannot
   delete another user's login (that needs the Admin SDK), and the project is on
   the **Spark plan**, where Cloud Functions cannot be deployed. So creating the
   login again failed with `email-already-in-use`, and the old password still
   signed in and quietly recreated an empty account for the "deleted" member.

What changed:

* **Delete User** now writes a `login_tombstones/{uid}` record first, removes
  the profile, the ownership record, contact/private copies, Aadhaar and **every
  `login_index` entry of the uid**, then `users/{uid}`. With the backend
  deployed it deletes the Firebase Auth record first.
* Without the backend, the tombstone makes the leftover login **delete itself**
  the next time anyone signs in with it (`AuthRepository._refuseRemovedLogin`,
  before any document is written) — which also frees the number and address.
* **Delete Login** (new) removes only the ability to sign in: the profile,
  chats, interests, horoscope documents and requests are kept, the number is
  released, and **Restore Login** gives it back to the same account.
* Creating a login now **inspects** what holds the number and shows the admin
  the account — phone, Firebase UID, profile status, account status — with safe
  choices: release a deleted login's registration, create the profile for the
  EXISTING account (no second login), replace an unused Firebase login
  (backend), or verify an old login with its current password (Spark).
* Registration refuses a number that already has a login (pre-check + atomic
  claim + rollback of the just-created login if another sign-up won the race).
* Profile creation is idempotent: repeated taps join the running save, and the
  ownership record makes retries / second devices land on the same document.

---

## 1b. Profile creation `permission-denied` (diagnosed 2026-09-17)

Checked, in order:

* **Project / App Check** — the app targets `matrimony-app-bd0d5`; App Check is
  *not* enforced for Firestore, so every refusal comes from the security rules.
* **Deployed rules** — the live ruleset (released 2026-09-16) is commit
  `aec7695`. Its `profiles`, `users` and `contacts` rules are identical to the
  2 Sep ruleset and ALLOW a signed-in member (password or Google) to query,
  create and edit their own profile. A guest (anonymous) or signed-out session,
  and any write to another member's profile, are refused — as intended. A guest
  who registers is upgraded in place and gets a `password`/`google.com` token
  (verified in the Auth emulator), so that is not the cause either.
* **What the deployed rules refuse in the flow** —
  `node tool/firestore_rules_test.js --live` runs the flow's exact requests
  against production: the only refusal is `profile_private/{uid}`, the private
  copy of hidden fields. The app has used it (and `contact_private`,
  `profile_owners`, `login_tombstones`, `password_reset_requests`,
  `account_reviews`) since commits whose rules were **never deployed** —
  Firestore denies any collection without a matching rule.
* **Where the raw text came from** — `[cloud_firestore/permission-denied] The
  caller does not have permission…` is `FirebaseException.toString()`. It was
  printed as-is by the admin Create Profile flow (e.g. "Verify & continue" on an
  old login reads `login_tombstones`), by the admin login actions, and by the
  Complete Profile screen.

Fixed in code (works on the current rules AND after deploying):

* Profile creation checks the session first — signed in, not a guest, saving
  the signed-in uid's own profile, token refreshed — and the required details,
  before uploading anything.
* The one-profile ownership record is probed with a plain read; the transaction
  only runs once its rules are live.
* The profile write must be **confirmed by the server** (30 s); a slow network
  is reported as a network error, and a retry reuses the same document.
* Every Firestore step is labelled: the developer log names the exact failing
  operation; the member sees a translated message (permission / network /
  session / missing details) — never the raw Firebase text.

The permanent fix is deploying the rules (§2).

## 2. Deploy the Firestore rules (REQUIRED)

```bash
firebase deploy --only firestore:rules
```

New / changed:

| Path | Rule |
|---|---|
| `users/{uid}` | members cannot raise their own `role`, lift `isBlocked`, or clear an admin's `authStatus`; admins may create a member record for an existing login |
| `login_index/{mobile}` | id must be 10 digits; admins may re-assign a number when restoring a login |
| `profiles/{id}` | a member creates only their OWN profile, with a non-empty `fullName` and `gender`, as `pending`, not verified and not a test profile, under the id in `profile_owners/{uid}` (admins: any member; dummy test profiles exempt). Owners cannot change `userId`, approve or verify themselves, or re-open a `blocked` profile; every other field stays editable |
| `profile_owners/{uid}` | **new** — see §0 |
| `login_tombstones/{uid}` | **new** — admin write; the account itself may read it at sign-in |
| `password_reset_requests/{mobile}_{day}` | **new** — any session (incl. guest) may *create* a pinned, password-free request, one per number per day; admin manages |
| `account_reviews/{key}` | **new** — admin only |
| `auth_rate_limits`, `auth_recovery_sessions` | **new** — backend only, no client access |

Verify the rules' behaviour without deploying anything (uses the Rules API test
endpoint; needs `firebase login`):

```bash
node tool/firestore_rules_test.js          # 70 cases against the repo rules
node tool/firestore_rules_test.js --live   # same requests against the DEPLOYED rules
```

> ⚠ Old app versions keep working with these rules (an account without an
> ownership record is not blocked). Once the new version is out, raise
> `latestVersionCode` in Admin → App Version so everyone moves to it.

---

## 3. Deploy the account backend (Blaze plan — REQUIRED for the full feature set)

`functions/accounts.js`, exported from `functions/index.js`:

| Function | Used for |
|---|---|
| `adminInspectLogin` | what really exists in Firebase Auth for a number / e-mail / UID |
| `adminProvisionLogin` | create a login, restore one **under the same UID**, replace an unused Firebase login (after confirmation) |
| `adminDeleteLogin` | delete the Firebase Auth record (keeping or not keeping data) |
| `adminSetTemporaryPassword` | admin-assisted recovery — one-time password, all sessions revoked, member must change it |
| `adminListAuthAccounts` | Account Health: deleted / unlinked login checks |
| `resetPasswordWithPhone` | OTP self-service recovery (hardened: fresh session ≤ 10 min, same number, one use, rate-limited, never picks between two profiles) |

Every admin function re-checks `users/{caller}.role` with the Admin SDK and all
of them enforce App Check. Passwords are never stored or logged; a temporary
password travels only in the callable response to the admin's device.

```bash
# needs the Blaze (pay-as-you-go) plan — see FIREBASE_SPARK note below
firebase deploy --only functions:adminInspectLogin,functions:adminProvisionLogin,functions:adminDeleteLogin,functions:adminSetTemporaryPassword,functions:adminListAuthAccounts,functions:resetPasswordWithPhone
```

Pure backend rules are unit-tested:

```bash
node --test functions/test/accountsCore.test.js
```

**On the Spark plan today** the app detects the missing backend and says so:
login creation and Delete User/Delete Login still work (tombstones instead of
Auth deletion), Account Health checks Firestore only, and temporary passwords /
same-UID restores / OTP recovery are unavailable. Blaze keeps the free tier;
set a budget alert when upgrading.

---

## 4. Password recovery

### Forgot Password → Mobile number + OTP (primary)

1. Registered number (must be in `login_index`, else → Contact Admin).
2. Firebase Phone Auth OTP — resend after 60 s, max 3 sends / 30 min per number
   on the device, 5 wrong codes per OTP, plus Firebase's own SMS quotas.
3. The OTP signs the device into a throwaway **phone** identity (never linked).
4. `resetPasswordWithPhone` (lookup) returns the resettable account(s), masked.
   Several login identities of ONE person → the member picks; a number on more
   than one matrimony profile → refused and flagged to the admin.
5. New password + confirmation.
6. The backend sets it, revokes every session of the account, marks the
   verification used and deletes the throwaway identity.

**Prerequisites:** Blaze plan (Phone Auth SMS is Blaze-only; Spark projects get
`BILLING_NOT_ENABLED`), *Authentication → Sign-in method → Phone* enabled, the
app's SHA-1/SHA-256 registered, and the backend deployed. WhatsApp OTP is **not**
offered: Firebase Phone Auth only delivers SMS.

### Forgot Password → E-mail

Firebase's reset link, for members with a real address. No backend needed.

### Contact Admin to Reset Password (always available)

Creates `password_reset_requests/{mobile}_{day}` with the number, an optional
name and a description — never a password or OTP. Admin → **Password Reset
Requests**: mark Under Review → verify through the registered number → identify
the account (resolved from the number) → send a Firebase reset e-mail to the
account's real address, or set a temporary password (backend) → Resolved /
Rejected with a note.

A temporary password sets `users/{uid}.mustChangePassword`; the router holds the
member on **Change Password** until they choose their own.

---

## 5. Admin panel

* **Users** — every row shows Profile Not Created / Profile Incomplete / Profile
  Completed / Login Deleted / Needs Review, with matching filters and a Create
  Profile action for members without one.
* **User Details → Login & Access** — Firebase UID, registered phone, login and
  profile status; Check login, Create profile, Delete login, Restore login,
  Temporary password. Delete User asks for the account facts + typed `DELETE`.
* **Create Profile** — Login Credentials step inspects the number first and
  offers the conflict choices from §1.
* **Accounts & Logins → Account Health** — duplicate numbers, multiple profiles
  on one UID, profiles whose login is gone, deleted logins still holding a
  number, unlinked Firebase logins, accounts without a Firebase login, index
  mismatches, missing ownership records, members without a profile. Each case is
  resolved individually; "Mark reviewed" leaves it as is.
* **Accounts & Logins → Password Reset Requests** — §4.

---

## 6. One-time cleanup after deploying (existing data)

1. Deploy the rules (§2).
2. Admin → **Account Health** → *Missing ownership records* → **Record ownership
   for all** (non-destructive; makes one-profile-per-account binding for
   existing members).
3. *Deleted login still holds a phone number* → **Release the number** for each
   (only the leftover registration is removed).
4. *Multiple profiles for one account* → open each, choose the profile to KEEP,
   confirm (typed `DELETE`).
5. *Duplicate phone number* → open the accounts, verify with the member, delete
   the wrong login (data kept) or mark reviewed. Nothing is merged
   automatically.
6. With the backend deployed, rescan for *Unlinked authentication account* /
   *Authentication account deleted* and resolve those the same way.

---

## 7. Admin "Create Matrimony Profile" (unchanged behaviour)

It still runs the **same** wizard members use plus a final **Login Credentials**
step, creates the login on a secondary Firebase app (the admin's session is
never swapped out), writes `users/{uid}` + the number claim from the new
member's session, and opens **Share Login Details** (WhatsApp) afterwards. A
success message is shown only after the server confirmed the writes.

App Check is activated on the secondary app on both its fresh and reused paths.
