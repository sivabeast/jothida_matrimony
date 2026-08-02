const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Keep the function close to the Firestore data it reads (same region as
// the rest of the project unless you deployed elsewhere).
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

// Set this once with:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
// (prompts securely in your terminal -- the key is never written to any
// file in this repo or typed anywhere else).
const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');

const ANTHROPIC_MODEL = 'claude-sonnet-5';
const MAX_MESSAGE_LENGTH = 1000;
const MAX_HISTORY_TURNS = 10;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const RATE_LIMIT_MAX_MESSAGES = 30;

const SYSTEM_PROMPT_BASE = `You are the AI assistant embedded on the Jothida Matrimony website and app.
Jothida Matrimony is a Tamil matrimony platform that also offers horoscope (jathagam) compatibility
matching and has exactly ONE official in-house astrologer (not a marketplace of astrologers).

You may help with:
- Explaining how the website/app works: Google sign-in (there is no separate registration form -- one
  tap of "Continue with Google" both logs a user in and creates their account), browsing features,
  how horoscope compatibility matching works in the app, how to reach the astrologer.
- General, educational explanations of Tamil astrology concepts (rasi, nakshatra, dasa, porutham,
  dosham types, etc.) at a conceptual level.
- Sharing the official astrologer's contact details (given to you below, if available) when asked how to
  reach them.
- General matrimony-related guidance (what makes a good profile, how horoscope matching factors into
  Tamil matchmaking, etc.).

You must NOT:
- Generate a personal horoscope reading, prediction, or compatibility verdict for a specific person's
  birth details -- that requires the real astrologer or the app's horoscope-matching feature. Politely
  redirect to the app's Horoscope Compatibility feature or to contacting the astrologer directly.
- Discuss, offer, or process appointment booking, scheduling, or any payment -- this site and bot are
  strictly informational. If asked to book something, say the astrologer must be contacted directly via
  the phone/WhatsApp/email shown on the site, and no booking happens through this chat.
- Give medical, legal, or financial advice.
- Answer questions unrelated to Jothida Matrimony, matrimony, or astrology (e.g. general coding help,
  news, unrelated trivia). Politely decline and steer the conversation back to what you can help with.

Style: reply in the same language/register the user writes in (Tamil, English, or Tanglish are all fine).
Keep answers concise and warm -- a few sentences, not an essay, unless the user clearly wants more detail.`;

/** Fetches the live astrologer contact details so the bot never gives stale info. */
async function loadAstrologerContext() {
  try {
    const snap = await db.doc('astrology_service/config').get();
    if (!snap.exists) return '';
    const d = snap.data() || {};
    const lines = [
      d.expertName ? `Astrologer name: ${d.expertName}` : null,
      d.expertSpecialization ? `Specialization: ${d.expertSpecialization}` : null,
      d.expertContactPhone || d.officeContactNumber
        ? `Phone: ${d.expertContactPhone || d.officeContactNumber}`
        : null,
      d.whatsappNumber ? `WhatsApp: ${d.whatsappNumber}` : null,
      d.email ? `Email: ${d.email}` : null,
      d.officeAddress ? `Office address: ${d.officeAddress}` : null,
    ].filter(Boolean);
    if (!lines.length) return '';
    return `\n\nCurrent official astrologer contact details (share these if asked how to reach the astrologer):\n${lines.join('\n')}`;
  } catch (err) {
    console.error('[chatWithAstrologyBot] failed to load astrologer context:', err);
    return '';
  }
}

/** Simple per-user hourly cap so one visitor can't run up the API bill. Best-effort, not perfectly atomic. */
async function enforceRateLimit(uid) {
  const ref = db.collection('chat_rate_limits').doc(uid);
  const now = Date.now();
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : null;

  if (!data || now - data.windowStart > RATE_LIMIT_WINDOW_MS) {
    await ref.set({ count: 1, windowStart: now });
    return;
  }
  if (data.count >= RATE_LIMIT_MAX_MESSAGES) {
    throw new HttpsError(
      'resource-exhausted',
      'You have sent a lot of messages recently. Please try again in a bit, or contact us directly.'
    );
  }
  await ref.update({ count: admin.firestore.FieldValue.increment(1) });
}

exports.chatWithAstrologyBot = onCall({ secrets: [ANTHROPIC_API_KEY] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign-in required.');
  }

  const message = typeof request.data?.message === 'string' ? request.data.message.trim() : '';
  if (!message) {
    throw new HttpsError('invalid-argument', 'message is required.');
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    throw new HttpsError('invalid-argument', `message must be under ${MAX_MESSAGE_LENGTH} characters.`);
  }

  const rawHistory = Array.isArray(request.data?.history) ? request.data.history : [];
  const history = rawHistory
    .filter((m) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
    .slice(-MAX_HISTORY_TURNS)
    .map((m) => ({ role: m.role, content: m.content.slice(0, 2000) }));

  await enforceRateLimit(request.auth.uid);

  const astrologerContext = await loadAstrologerContext();
  const systemPrompt = `${SYSTEM_PROMPT_BASE}${astrologerContext}`;

  const messages = [...history, { role: 'user', content: message }];

  let response;
  try {
    response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY.value(),
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 512,
        system: systemPrompt,
        messages,
      }),
    });
  } catch (err) {
    console.error('[chatWithAstrologyBot] network error calling Anthropic:', err);
    throw new HttpsError('unavailable', 'The assistant is temporarily unavailable. Please try again shortly.');
  }

  if (!response.ok) {
    const errText = await response.text().catch(() => '');
    console.error('[chatWithAstrologyBot] Anthropic API error:', response.status, errText);
    throw new HttpsError('internal', 'The assistant is temporarily unavailable. Please try again shortly.');
  }

  const data = await response.json();
  const reply = data?.content?.find((block) => block.type === 'text')?.text
    || "Sorry, I couldn't come up with a reply just now. Please try again.";

  return { reply };
});

// ─────────────────────────────────────────────────────────────────────────────
// Password reset by MOBILE NUMBER (OTP verified).
//
// The app supports two password login identifiers: mobile number and e-mail.
// "Forgot password" by e-mail is handled entirely by Firebase (reset link), but
// a member who only has a mobile number needs a server-side reset: the Firebase
// client SDK can only change the password of the account it is signed into, and
// verifying an SMS code signs the device into the PHONE-provider identity, not
// into the member's password account.
//
// Flow enforced here:
//   1. the app verifies the SMS code with Firebase Phone Auth, which produces a
//      short-lived session whose token carries `phone_number` and
//      sign_in_provider == 'phone';
//   2. this function checks that the verified number is exactly the number the
//      caller is trying to reset — so possession of the SIM is proven;
//   3. it resolves that number to the owning account through `login_index` and
//      sets the new password with the Admin SDK;
//   4. the throwaway phone-provider identity created in step 1 is deleted, so
//      OTP resets never litter Firebase Auth with orphan accounts.
//
// Deploy with:  firebase deploy --only functions:resetPasswordWithPhone
// ─────────────────────────────────────────────────────────────────────────────

const MIN_PASSWORD_LENGTH = 6;

/** Digits-only Indian number without the country code, or '' when invalid. */
function localMobile(raw) {
  let digits = String(raw || '').replace(/[^0-9]/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  if (digits.length === 12 && digits.startsWith('91')) digits = digits.slice(2);
  return digits.length === 10 ? digits : '';
}

exports.resetPasswordWithPhone = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError('unauthenticated', 'Verify the OTP before resetting your password.');
  }

  const provider = auth.token?.firebase?.sign_in_provider;
  if (provider !== 'phone') {
    throw new HttpsError('permission-denied', 'This reset requires an OTP-verified phone session.');
  }

  const verified = localMobile(auth.token?.phone_number);
  const requested = localMobile(request.data?.mobile);
  if (!verified || !requested || verified !== requested) {
    throw new HttpsError('permission-denied', 'The verified number does not match the number being reset.');
  }

  const newPassword = String(request.data?.newPassword || '');
  if (newPassword.length < MIN_PASSWORD_LENGTH) {
    throw new HttpsError('invalid-argument', `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
  }

  const indexSnap = await db.collection('login_index').doc(verified).get();
  const targetUid = indexSnap.exists ? indexSnap.data().uid : null;
  if (!targetUid) {
    // Deliberately vague: never reveal whether a number has an account.
    throw new HttpsError('not-found', 'No password account is registered for this mobile number.');
  }

  await admin.auth().updateUser(targetUid, { password: newPassword });
  console.log(`[resetPasswordWithPhone] password reset for uid=${targetUid}`);

  // Clean up the throwaway phone identity, unless the OTP session IS the
  // account (i.e. the phone number is linked to it directly).
  if (auth.uid !== targetUid) {
    try {
      await admin.auth().deleteUser(auth.uid);
    } catch (err) {
      console.warn('[resetPasswordWithPhone] temp phone identity cleanup skipped:', err);
    }
  }

  return { ok: true };
});

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PIPELINE
//
// One rule keeps pushes exactly-once: `onNotificationCreated` is the SINGLE
// push gate for `notifications/{id}` documents. Event triggers below never
// send a push for a doc they merely "ensure": they upsert with a DETERMINISTIC
// id via set(merge) — if the client already wrote the doc, the server write is
// an update (no create event, no second push); if the client failed/offline,
// the server write IS the create and the push fires once. Docs that a trigger
// pushes ITSELF carry `pushed: true`, which the gate skips.
// ─────────────────────────────────────────────────────────────────────────────

/** Bilingual notification templates keyed by receiver language. */
const NOTIF_TEMPLATES = {
  interest_received: {
    en: (name) => ({
      title: 'New Interest 💌',
      body: `${name || 'Someone'} has shown interest in your profile. Take a look!`,
    }),
    ta: (name) => ({
      title: 'புதிய விருப்பம் 💌',
      body: `${name || 'ஒருவர்'} உங்கள் Profile-இல் விருப்பம் தெரிவித்துள்ளார். இப்போது பார்க்கலாம்!`,
    }),
  },
  interest_accepted: {
    en: (name) => ({
      title: 'Interest Accepted 🎉',
      body: `${name || 'A member'} accepted your interest. Start chatting now!`,
    }),
    ta: (name) => ({
      title: 'விருப்பம் ஏற்கப்பட்டது 🎉',
      body: `${name || 'ஒரு உறுப்பினர்'} உங்கள் விருப்பத்தை ஏற்றுக்கொண்டார். இப்போது அரட்டையைத் தொடங்குங்கள்!`,
    }),
  },
  interest_rejected: {
    en: (name) => ({
      title: 'Interest Update',
      body: `${name || 'A member'} has declined your interest.`,
    }),
    ta: (name) => ({
      title: 'விருப்ப நிலை',
      body: `${name || 'ஒரு உறுப்பினர்'} உங்கள் விருப்பத்தை நிராகரித்துள்ளார்.`,
    }),
  },
  chat_message: {
    en: (name) => ({
      title: 'New Message 💬',
      body: `${name || 'A member'} sent you a new message.`,
    }),
    ta: (name) => ({
      title: 'புதிய செய்தி 💬',
      body: `${name || 'ஒரு உறுப்பினர்'} உங்களுக்கு புதிய செய்தி அனுப்பியுள்ளார்.`,
    }),
  },
  new_match: {
    en: () => ({
      title: 'New Matching Profile ✨',
      body: 'A new profile matching your preferences has joined. Take a look!',
    }),
    ta: () => ({
      title: 'புதிய பொருத்தமான Profile ✨',
      body: 'உங்கள் விருப்பங்களுக்கு பொருந்தும் புதிய Profile இணைந்துள்ளது. இப்போது பார்க்கலாம்!',
    }),
  },
};

/** The greeting the ACCEPTER "sends" as the first chat message (mirrors the
 *  client-side kInterestAcceptedFirstMessage constants). */
const GREETING = {
  en:
    'Hi! I have accepted your interest. We are now connected. ' +
    'Feel free to start the conversation.',
  ta:
    'வணக்கம்! உங்கள் விருப்பத்தை நான் ஏற்றுக்கொண்டேன். ' +
    'இப்போது நாம் இணைக்கப்பட்டுள்ளோம். தயங்காமல் உரையாடலைத் தொடங்கலாம்.',
};

const FieldValue = admin.firestore.FieldValue;

/** users/{uid} doc data or null. */
async function getUser(uid) {
  if (!uid) return null;
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists ? snap.data() : null;
}

/** The (first) profile doc owned by uid, or null. */
async function getProfileByUserId(uid) {
  if (!uid) return null;
  const q = await db
    .collection('profiles')
    .where('userId', '==', uid)
    .limit(1)
    .get();
  return q.empty ? null : { id: q.docs[0].id, ...q.docs[0].data() };
}

/** Display name of uid's profile in the receiver's language. */
function profileDisplayName(profile, lang) {
  if (!profile) return '';
  const ta = String(profile.fullNameTamil || '').trim();
  const en = String(profile.fullName || '').trim();
  return lang === 'ta' ? (ta || en) : (en || ta);
}

function templateFor(type, lang, name) {
  const t = NOTIF_TEMPLATES[type];
  if (!t) return null;
  return (lang === 'ta' ? t.ta : t.en)(name);
}

/**
 * Sends one FCM message to [uid]'s registered device (if any), and clears the
 * stored token when FCM reports it invalid/expired so it is never retried.
 */
async function pushToUser(uid, { title, body, route, type, collapseKey }) {
  const user = await getUser(uid);
  const token = user && typeof user.fcmToken === 'string' ? user.fcmToken : '';
  if (!token) return false;
  const message = {
    token,
    notification: { title, body },
    data: {
      route: route || '',
      type: type || '',
    },
    android: {
      priority: 'high',
      collapseKey: collapseKey || undefined,
      // No channelId: the app creates no custom channel, so naming one would
      // silently fall back to the low-importance "Miscellaneous" channel.
      // The FCM default channel + high priority shows tray + sound reliably.
      notification: {
        priority: 'high',
        defaultSound: true,
      },
    },
    apns: {
      payload: { aps: { sound: 'default', badge: 1 } },
    },
  };
  try {
    await admin.messaging().send(message);
    return true;
  } catch (err) {
    const code = err && err.code ? String(err.code) : '';
    if (
      code.includes('registration-token-not-registered') ||
      code.includes('invalid-registration-token') ||
      code.includes('invalid-argument')
    ) {
      console.log(`[push] clearing invalid token for uid=${uid} (${code})`);
      try {
        await db.collection('users').doc(uid).update({
          fcmToken: FieldValue.delete(),
        });
      } catch (cleanupErr) {
        console.warn('[push] token cleanup failed:', cleanupErr);
      }
    } else {
      console.warn(`[push] send to uid=${uid} failed:`, err);
    }
    return false;
  }
}

// ── 1) The single push gate ──────────────────────────────────────────────────
// Any `notifications/{id}` document created WITHOUT `pushed: true` gets
// delivered as a real device push. This covers every client-written
// notification (interest events, report ready, appointments, admin updates,
// horoscope events…) with ONE trigger and zero extra Firestore writes.
exports.onNotificationCreated = onDocumentCreated(
  'notifications/{notificationId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const n = snap.data();
    if (!n || n.pushed === true) return; // pushed explicitly by its own trigger
    const uid = String(n.userId || '');
    if (!uid) return;
    const route = n.data && n.data.route ? String(n.data.route) : '';
    await pushToUser(uid, {
      title: String(n.title || ''),
      body: String(n.body || ''),
      route,
      type: String(n.type || ''),
      collapseKey: event.params.notificationId,
    });
  }
);

/**
 * Creates a notification doc ONLY when it doesn't exist yet. Never touches an
 * existing doc — the client may have already written it and the receiver may
 * have already READ it; a merge would flip it back to unread and re-stamp
 * createdAt. create() is atomic (fails with ALREADY_EXISTS on a race).
 */
async function createNotificationIfAbsent(id, doc) {
  try {
    await db.collection('notifications').doc(id).create(doc);
    return true;
  } catch (err) {
    const code = err && (err.code === 6 || String(err.code) === '6' ||
        String(err.message || '').includes('ALREADY_EXISTS'));
    if (!code) console.warn(`[notif] create ${id} failed:`, err);
    return false;
  }
}

// ── 2) Interest lifecycle ────────────────────────────────────────────────────
// Safety-net notification docs (deterministic ids — see pipeline note) plus
// the server-side guarantee that an ACCEPTED interest always has its chat
// thread + greeting, even if the accepting device died mid-flow.
exports.onInterestWritten = onDocumentWritten(
  'interests/{interestId}',
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    const interestId = event.params.interestId;

    // DELETED (withdrawn) → remove its notifications so the receiver can
    // never act on an interest that no longer exists. Guard against
    // out-of-order events: if the interest was RE-SENT before this delete
    // event ran, the doc exists again and the live notification must stay.
    if (!after) {
      const stillDeleted = !(await db
        .collection('interests')
        .doc(interestId)
        .get()).exists;
      if (!stillDeleted) return;
      const ids = [
        `interest_received_${interestId}`,
        `interest_accepted_${interestId}`,
        `interest_rejected_${interestId}`,
      ];
      await Promise.all(
        ids.map((id) =>
          db.collection('notifications').doc(id).delete().catch(() => {})
        )
      );
      return;
    }

    const senderId = String(after.senderId || '');
    const receiverId = String(after.receiverId || '');
    if (!senderId || !receiverId) return;

    // CREATED (pending) → ensure the receiver's "New Interest" notification.
    if (!before && after.status === 'pending') {
      // CROSS-SEND CLEANUP: rules deny a create while the reverse doc exists,
      // but two truly simultaneous creates can both slip through (the rule
      // exists() checks are not serialized against each other). Keep the
      // OLDER interest, delete the newer duplicate; on a timestamp tie keep
      // the lexicographically smaller doc id. Both events run this same
      // deterministic logic, so exactly one doc survives.
      const [sp, rp] = interestId.split('_');
      if (sp && rp) {
        const reverseSnap = await db
          .collection('interests')
          .doc(`${rp}_${sp}`)
          .get();
        if (reverseSnap.exists && reverseSnap.data().status === 'pending' &&
            after.status === 'pending') {
          const mine = after.sentAt && after.sentAt.toMillis
            ? after.sentAt.toMillis() : 0;
          const theirs = reverseSnap.data().sentAt &&
              reverseSnap.data().sentAt.toMillis
            ? reverseSnap.data().sentAt.toMillis() : 0;
          const iAmNewer = mine > theirs ||
              (mine === theirs && interestId > reverseSnap.id);
          if (iAmNewer) {
            console.log(`[interest] cross-send duplicate ${interestId} deleted`);
            await event.data.after.ref.delete().catch(() => {});
            return; // the delete event cleans up the notification
          }
        }
      }

      const receiver = await getUser(receiverId);
      const lang = receiver && receiver.preferred_language === 'ta' ? 'ta' : 'en';
      const senderProfile = await getProfileByUserId(senderId);
      const t = templateFor(
        'interest_received', lang, profileDisplayName(senderProfile, lang));
      await createNotificationIfAbsent(`interest_received_${interestId}`, {
        userId: receiverId,
        title: t.title,
        body: t.body,
        type: 'interest_received',
        data: { route: `/interests?tab=received&highlight=${senderId}` },
        isRead: false,
        senderId,
        targetScreen: 'interests',
        targetId: interestId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    // STATUS TRANSITION (pending → accepted / rejected).
    const statusBefore = before ? String(before.status || '') : '';
    const statusAfter = String(after.status || '');
    if (statusBefore === statusAfter) return;

    if (statusAfter === 'accepted') {
      await ensureAcceptedChat(interestId, senderId, receiverId);
      const sender = await getUser(senderId);
      const lang = sender && sender.preferred_language === 'ta' ? 'ta' : 'en';
      const accepterProfile = await getProfileByUserId(receiverId);
      const t = templateFor(
        'interest_accepted', lang, profileDisplayName(accepterProfile, lang));
      await createNotificationIfAbsent(`interest_accepted_${interestId}`, {
        userId: senderId,
        title: t.title,
        body: t.body,
        type: 'interest_accepted',
        data: { route: `/interests?tab=accepted&highlight=${receiverId}` },
        isRead: false,
        senderId: receiverId,
        targetScreen: 'interests',
        targetId: interestId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (statusAfter === 'rejected') {
      const sender = await getUser(senderId);
      const lang = sender && sender.preferred_language === 'ta' ? 'ta' : 'en';
      const rejecterProfile = await getProfileByUserId(receiverId);
      const t = templateFor(
        'interest_rejected', lang, profileDisplayName(rejecterProfile, lang));
      await createNotificationIfAbsent(`interest_rejected_${interestId}`, {
        userId: senderId,
        title: t.title,
        body: t.body,
        type: 'interest_rejected',
        data: { route: `/interests?tab=rejected&highlight=${receiverId}` },
        isRead: false,
        senderId: receiverId,
        targetScreen: 'interests',
        targetId: interestId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }
);

/**
 * Guarantees the accepted-interest conversation exists and starts with the
 * greeting: chats/{threadId} (deterministic sorted-uid id) + a
 * `greeting_{threadId}` message from the ACCEPTER. Fully idempotent — the
 * client normally does all of this instantly; this is the safety net.
 */
async function ensureAcceptedChat(interestId, senderId, receiverId) {
  try {
    const threadId = [senderId, receiverId].sort().join('_');
    const threadRef = db.collection('chats').doc(threadId);
    const greetingRef = threadRef.collection('messages').doc(`greeting_${threadId}`);

    const [threadSnap, greetingSnap, senderProfile, receiverProfile, receiverUser] =
      await Promise.all([
        threadRef.get(),
        greetingRef.get(),
        getProfileByUserId(senderId),
        getProfileByUserId(receiverId),
        getUser(receiverId),
      ]);

    if (!threadSnap.exists) {
      await threadRef.set(
        {
          participantIds: [senderId, receiverId],
          participantNames: {
            [senderId]: profileDisplayName(senderProfile, 'en') || 'Member',
            [receiverId]: profileDisplayName(receiverProfile, 'en') || 'Member',
          },
          participantPhotos: {
            [senderId]: (senderProfile && senderProfile.profilePhotoUrl) || '',
            [receiverId]: (receiverProfile && receiverProfile.profilePhotoUrl) || '',
          },
          unread: { [senderId]: 0, [receiverId]: 0 },
          createdAt: FieldValue.serverTimestamp(),
          lastMessageAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    // Greeting: only when neither the greeting nor any other message exists.
    // A TRANSACTION (not check-then-write) so a client greeting committing
    // concurrently aborts/retries this instead of double-posting or
    // double-incrementing the sender's unread badge.
    if (!greetingSnap.exists) {
      const lang =
        receiverUser && receiverUser.preferred_language === 'ta' ? 'ta' : 'en';
      const text = GREETING[lang];
      await db.runTransaction(async (txn) => {
        const anyMessage =
          await txn.get(threadRef.collection('messages').limit(1));
        if (!anyMessage.empty) return; // client already greeted / chatted
        txn.set(greetingRef, {
          senderId: receiverId, // the ACCEPTER greets
          text,
          sentAt: FieldValue.serverTimestamp(),
          type: 'text',
        });
        txn.set(
          threadRef,
          {
            lastMessage: text,
            lastSenderId: receiverId,
            lastMessageAt: FieldValue.serverTimestamp(),
            [`unread.${senderId}`]: FieldValue.increment(1),
          },
          { merge: true }
        );
      });
    }
    console.log(`[ensureAcceptedChat] ok interest=${interestId} thread=${threadId}`);
  } catch (err) {
    console.error(`[ensureAcceptedChat] failed for ${interestId}:`, err);
  }
}

// ── 3) Chat messages ─────────────────────────────────────────────────────────
// Push (+ one UPSERTED notification doc per conversation) for every message
// whose receiver is not currently viewing that conversation. The per-thread
// deterministic doc id keeps the notification feed clean — one row per
// conversation, refreshed and marked unread on each new message.
exports.onChatMessageCreated = onDocumentCreated(
  'chats/{threadId}/messages/{messageId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const { threadId, messageId } = event.params;
    // The greeting is announced by the interest-accepted notification already.
    if (messageId.startsWith('greeting_')) return;

    const msg = snap.data();
    const senderId = String(msg.senderId || '');
    if (!senderId) return;

    const threadSnap = await db.collection('chats').doc(threadId).get();
    if (!threadSnap.exists) return;
    const participants = threadSnap.data().participantIds || [];
    const receiverId = participants.find((p) => p && p !== senderId);
    if (!receiverId) return;

    const receiver = await getUser(receiverId);
    if (!receiver) return;
    // Presence: no push while the receiver is looking at this conversation —
    // but the notification row is still kept current (marked read, since they
    // are literally reading the chat). The client clears the marker on
    // background/leave and at app start, so a stale marker can't suppress
    // pushes for long.
    const viewing = String(receiver.activeThreadId || '') === threadId;

    const lang = receiver.preferred_language === 'ta' ? 'ta' : 'en';
    const senderName =
      (threadSnap.data().participantNames || {})[senderId] || '';
    const t = templateFor('chat_message', lang, senderName);

    // One row per conversation. createdAt is REFRESHED on every message —
    // the feed queries/sorts by createdAt (limit 50), so a stale createdAt
    // would leave the refreshed row buried or dropped entirely.
    const notifRef = db
      .collection('notifications')
      .doc(`chat_${threadId}_${receiverId}`);
    await notifRef.set(
      {
        userId: receiverId,
        title: t.title,
        body: t.body,
        type: 'chat_message',
        data: { route: `/chat/${threadId}` },
        isRead: viewing,
        senderId,
        targetScreen: 'chat',
        targetId: threadId,
        pushed: true, // this trigger pushes itself (every message, not once)
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (viewing) return;
    await pushToUser(receiverId, {
      title: t.title,
      body: t.body,
      route: `/chat/${threadId}`,
      type: 'chat_message',
      collapseKey: threadId,
    });
  }
);

// ── 4) New matching profile ──────────────────────────────────────────────────
// When a profile becomes VISIBLE (created approved, or approved later), notify
// ONLY the members whose saved partner preferences the new profile satisfies.

/** Lenient server-side port of the app's mandatoryPreferenceMatch: every SET
 *  preference must match; unset prefs and missing candidate data pass. */
function matchesPreferences(prefs, candidate) {
  if (!prefs) return true;
  const set = (v) =>
    v !== undefined && v !== null && String(v).trim() !== '' &&
    String(v).trim().toLowerCase() !== 'any';
  const eq = (a, b) =>
    String(a).trim().toLowerCase() === String(b).trim().toLowerCase();
  const gate = (prefVal, candVal) =>
    !set(prefVal) || !set(candVal) || eq(prefVal, candVal);

  const age = Number(candidate.age || 0);
  if (prefs.agePreferenceSet === true && age > 0) {
    const min = Number(prefs.minAge || 18);
    const max = Number(prefs.maxAge || 99);
    if (age < min || age > max) return false;
  }
  if (!gate(prefs.religion, candidate.religion)) return false;
  if (!gate(prefs.caste, candidate.caste)) return false;
  if (!gate(prefs.subCaste, candidate.subCaste)) return false;
  if (!gate(prefs.maritalStatus, candidate.maritalStatus)) return false;
  if (!gate(prefs.motherTongue, candidate.motherTongue)) return false;
  if (!gate(prefs.physicalStatus, candidate.physicalStatus)) return false;
  if (!gate(prefs.country, candidate.country)) return false;
  if (!gate(prefs.state, candidate.state)) return false;
  if (!gate(prefs.district, candidate.district)) return false;
  if (!gate(prefs.city, candidate.city)) return false;
  const listGate = (prefList, candVal) => {
    if (!Array.isArray(prefList) || prefList.length === 0) return true;
    if (!set(candVal)) return true;
    return prefList.some((p) => eq(p, candVal));
  };
  if (!listGate(prefs.education, candidate.education)) return false;
  if (!listGate(prefs.occupation, candidate.occupation)) return false;
  return true;
}

const NEW_MATCH_MAX_RECIPIENTS = 300;

exports.onProfileWritten = onDocumentWritten(
  'profiles/{profileId}',
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;

    const visible = (p) =>
      p && p.status === 'approved' && p.isActive === true && p.isDummy !== true;
    // Fire exactly when the profile FIRST becomes visible: brand-new approved
    // doc, or first pending→approved transition. Reactivations (unblock,
    // un-married, account reactivate) also flip visibility but must never
    // re-blast "new profile" pushes — the newMatchNotifiedAt stamp makes this
    // once-per-profile regardless of how visibility toggles later.
    if (!visible(after) || visible(before)) return;
    if (after.newMatchNotifiedAt) return; // already announced once
    const firstReveal =
      !before || String(before.status || '') === 'pending';
    if (!firstReveal) return;

    const profileId = event.params.profileId;
    const newUid = String(after.userId || '');
    const gender = String(after.gender || '').trim().toLowerCase();
    if (!newUid || !gender) return;
    await event.data.after.ref
      .update({ newMatchNotifiedAt: FieldValue.serverTimestamp() })
      .catch(() => {});
    const oppositeGender = gender === 'male' ? 'Female' : 'Male';

    // Candidate audience: visible opposite-gender profiles (bounded).
    const candidates = await db
      .collection('profiles')
      .where('status', '==', 'approved')
      .where('isActive', '==', true)
      .where('gender', '==', oppositeGender)
      .limit(500)
      .get();

    const recipients = [];
    for (const doc of candidates.docs) {
      const p = doc.data();
      const uid = String(p.userId || '');
      if (!uid || uid === newUid || p.isDummy === true) continue;
      if (!matchesPreferences(p.partnerPreferences, after)) continue;
      recipients.push(uid);
      if (recipients.length >= NEW_MATCH_MAX_RECIPIENTS) break;
    }
    if (recipients.length === 0) return;
    console.log(
      `[newMatch] profile=${profileId} notifying ${recipients.length} member(s)`);

    // Batched notification docs (deterministic ids → no duplicates on
    // re-approval) + individual pushes with per-user language.
    const batches = [];
    let batch = db.batch();
    let inBatch = 0;
    for (const uid of recipients) {
      batch.set(
        db.collection('notifications').doc(`new_profile_${profileId}_${uid}`),
        {
          userId: uid,
          title: NOTIF_TEMPLATES.new_match.en().title,
          body: NOTIF_TEMPLATES.new_match.en().body,
          type: 'new_match',
          data: { route: `/profile/${profileId}` },
          isRead: false,
          senderId: '',
          targetScreen: 'profile',
          targetId: profileId,
          pushed: true, // pushed below with per-user language
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      if (++inBatch >= 450) {
        batches.push(batch.commit());
        batch = db.batch();
        inBatch = 0;
      }
    }
    if (inBatch > 0) batches.push(batch.commit());
    await Promise.all(batches);

    // Pushes — small chunks to stay well inside quota/connection limits.
    const CHUNK = 20;
    for (let i = 0; i < recipients.length; i += CHUNK) {
      await Promise.all(
        recipients.slice(i, i + CHUNK).map(async (uid) => {
          const user = await getUser(uid);
          const lang = user && user.preferred_language === 'ta' ? 'ta' : 'en';
          const t = templateFor('new_match', lang, '');
          await pushToUser(uid, {
            title: t.title,
            body: t.body,
            route: `/profile/${profileId}`,
            type: 'new_match',
            collapseKey: `new_profile_${profileId}`,
          });
        })
      );
    }
  }
);

// ── 5) Admin announcements ───────────────────────────────────────────────────
// One TOPIC send per announcement (clients subscribe to 'users'/'employees'
// at login) — no per-user fan-out writes. The announcement document itself is
// the stored history shown in every user's notification feed.
exports.onAnnouncementCreated = onDocumentCreated(
  'announcements/{announcementId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const a = snap.data();
    if (!a || a.isActive === false) return;
    // Future-scheduled announcements are not pushed at create time.
    if (a.scheduledAt && a.scheduledAt.toMillis &&
        a.scheduledAt.toMillis() > Date.now()) {
      console.log(`[announcement] ${event.params.announcementId} scheduled — skip push`);
      return;
    }
    const topic = a.audience === 'employees' ? 'employees' : 'users';
    const title = String(a.title || '').slice(0, 200);
    const body = String(a.message || '').slice(0, 500);
    const route = `/announcement/${event.params.announcementId}`;
    try {
      await admin.messaging().send({
        topic,
        notification: { title, body },
        data: { route, type: 'announcement' },
        android: {
          priority: 'high',
          notification: {
            priority: 'high',
            defaultSound: true,
          },
        },
        apns: { payload: { aps: { sound: 'default' } } },
      });
      console.log(`[announcement] pushed to topic=${topic}`);
    } catch (err) {
      console.error('[announcement] topic push failed:', err);
    }
  }
);
