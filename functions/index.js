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
