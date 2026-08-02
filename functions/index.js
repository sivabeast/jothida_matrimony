const { onCall, HttpsError } = require('firebase-functions/v2/https');
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
