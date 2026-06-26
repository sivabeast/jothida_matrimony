/**
 * Jothida Matrimony — Cloud Functions (spec §8/§9/§12).
 *
 * Two responsibilities:
 *   1. onNotificationCreated — turn every `notifications/{id}` document the app
 *      writes into a real FCM device push. Because the whole app already records
 *      a notification doc for every event (new request, accepted, completed,
 *      reminders, expiry…), this single trigger gives push for ALL of them.
 *   2. matchAnalysisSweep — a scheduled job that, for every PENDING match-
 *      analysis booking, sends the "6 / 3 / 1 hours remaining" reminders and
 *      auto-expires bookings the astrologer didn't accept within 12 WORKING
 *      hours. Working hours exclude 00:00–07:00 IST, exactly like the on-device
 *      countdown (lib/core/utils/working_hours.dart).
 */
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {setGlobalOptions} = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Run close to the users (Mumbai) and cap concurrency cost.
setGlobalOptions({region: "asia-south1", maxInstances: 10});

// ── Working-hour helpers (IST) — mirror of working_hours.dart ────────────────
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;
const ONE_HOUR = 60 * 60 * 1000;
const SIX_HOURS = 6 * ONE_HOUR;
const THREE_HOURS = 3 * ONE_HOUR;

/** IST wall-clock hour (0–23) for an epoch-ms instant. */
function istHour(ms) {
  return new Date(ms + IST_OFFSET_MS).getUTCHours();
}

/** Epoch ms of 07:00 IST on the IST-day containing [ms]. */
function istSeven(ms) {
  const d = new Date(ms + IST_OFFSET_MS);
  d.setUTCHours(7, 0, 0, 0);
  return d.getTime() - IST_OFFSET_MS;
}

/** Epoch ms of the next IST midnight after [ms]. */
function istNextMidnight(ms) {
  const d = new Date(ms + IST_OFFSET_MS);
  d.setUTCHours(24, 0, 0, 0);
  return d.getTime() - IST_OFFSET_MS;
}

/**
 * Amount of WORKING time (ms) between [fromMs] and [toMs], excluding the
 * 00:00–07:00 IST band each day. Zero if [toMs] <= [fromMs].
 */
function workingMsBetween(fromMs, toMs) {
  if (toMs <= fromMs) return 0;
  let cur = fromMs;
  let total = 0;
  let guard = 0;
  while (cur < toMs && guard++ < 2000) {
    let c = cur;
    if (istHour(c) < 7) c = istSeven(c); // clamp forward to 07:00 IST
    if (c >= toMs) break;
    const segEnd = Math.min(istNextMidnight(c), toMs);
    if (segEnd > c) total += segEnd - c;
    cur = istNextMidnight(c);
  }
  return total;
}

// ── 1. Push delivery: notifications/{id} onCreate → FCM ──────────────────────
exports.onNotificationCreated = onDocumentCreated(
    "notifications/{id}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const n = snap.data() || {};
      const userId = n.userId;
      if (!userId) return;

      const userSnap = await db.collection("users").doc(userId).get();
      const token = userSnap.exists ? userSnap.get("fcmToken") : null;
      if (!token) {
        logger.info(`No fcmToken for ${userId}; skipping push.`);
        return;
      }

      // All data values must be strings for FCM.
      const data = {type: String(n.type || "")};
      if (n.data && typeof n.data === "object") {
        for (const k of Object.keys(n.data)) {
          data[k] = String(n.data[k]);
        }
      }

      try {
        await admin.messaging().send({
          token,
          notification: {title: n.title || "", body: n.body || ""},
          data,
          android: {
            priority: "high",
            notification: {
              channelId: "high_importance_channel",
              sound: "default",
            },
          },
          apns: {payload: {aps: {sound: "default"}}},
        });
      } catch (e) {
        logger.error(`FCM send failed for ${userId}: ${e}`);
        // Token expired/unregistered → clean it up so we stop retrying.
        if (
          e.code === "messaging/registration-token-not-registered" ||
          e.code === "messaging/invalid-registration-token"
        ) {
          await db
              .collection("users")
              .doc(userId)
              .update({fcmToken: admin.firestore.FieldValue.delete()})
              .catch(() => {});
        }
      }
    },
);

/** Best-effort: write a notification doc (which the trigger above turns into a
 * push). */
async function notify(userId, title, body, type, data) {
  if (!userId) return;
  await db.collection("notifications").add({
    userId,
    title,
    body,
    type,
    data: data || {},
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/** "Groom × Bride" label from a raw request doc. */
function pairLabel(r) {
  const g = r.groomProfileName || r.profileAName || "Groom";
  const b = r.brideProfileName || r.profileBName || "Bride";
  return `${g} × ${b}`;
}

// ── 1b. Booking events → notifications (authored server-side) ────────────────
// Clients cannot create notification docs (rules: admin-only), so the booking
// notifications are authored here, where the admin SDK bypasses rules. Each doc
// then fans out to a device push via onNotificationCreated above.

exports.onMatchRequestCreated = onDocumentCreated(
    "astrologer_requests/{id}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const r = snap.data() || {};
      if (r.type !== "matching") return;
      const id = event.params.id;
      const pair = pairLabel(r);
      const route = `/match-workspace/${id}`;
      await notify(
          r.astrologerId,
          "New Match Analysis Request",
          `${r.userName || "A user"} paid for a match analysis (${pair}). ` +
        "Accept within 12 working hours.",
          "new_match_analysis",
          {requestId: id, route},
      );
      await notify(
          r.userId,
          "Payment Successful",
          "Your payment was received and your match-analysis booking was sent " +
        `to ${r.astrologerName || "the astrologer"}.`,
          "payment_success",
          {requestId: id, route: "/my-analysis"},
      );
    },
);

exports.onMatchRequestUpdated = onDocumentUpdated(
    "astrologer_requests/{id}",
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      if (after.type !== "matching") return;
      const id = event.params.id;
      const userRoute = "/my-analysis";
      const who = after.astrologerName || "The astrologer";

      if (before.status !== after.status) {
        if (after.status === "accepted") {
          await notify(after.userId, "Booking Accepted",
              `${who} accepted your match-analysis request.`,
              "booking_accepted", {requestId: id, route: userRoute});
        } else if (after.status === "rejected") {
          await notify(after.userId, "Booking Declined",
              `${who} is unable to take your request right now.`,
              "booking_rejected", {requestId: id, route: userRoute});
        } else if (after.status === "completed") {
          await notify(after.userId, "Report Ready",
              `Your analysis report from ${who} is ready to view.`,
              "porutham_ready", {requestId: id, route: userRoute});
        }
      }
      // Accepted → Analysis In Progress (spec §11).
      if (before.inProgress !== true && after.inProgress === true) {
        await notify(after.userId, "Analysis In Progress",
            `${who} has started your match analysis.`,
            "analysis_started", {requestId: id, route: userRoute});
      }
    },
);

// ── 1c. Direct-visit booking events → notifications ──────────────────────────
exports.onConsultationCreated = onDocumentCreated(
    "consultations/{id}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const c = snap.data() || {};
      if (c.mode !== "directVisit") return; // only Direct Visit remains
      const id = event.params.id;
      await notify(
          c.astrologerId,
          "New Direct Visit Booking",
          `${c.userName || "A user"} requested a direct visit. ` +
        "Accept or decline the appointment.",
          "new_direct_visit",
          {consultationId: id, route: "/astrologer-requests?tab=visit"},
      );
    },
);

exports.onConsultationUpdated = onDocumentUpdated(
    "consultations/{id}",
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      if (after.mode !== "directVisit") return;
      if (before.status === after.status) return;
      const who = after.astrologerName || "The astrologer";
      if (after.status === "accepted") {
        await notify(after.userId, "Visit Confirmed",
            `${who} confirmed your direct-visit appointment.`,
            "consultation_accepted", {route: "/my-consultations"});
      } else if (after.status === "rejected" || after.status === "cancelled") {
        await notify(after.userId, "Appointment Cancelled",
            `Your direct-visit appointment with ${who} was cancelled.`,
            "consultation_cancelled", {route: "/my-consultations"});
      } else if (after.status === "completed") {
        await notify(after.userId, "Visit Completed",
            `Your direct visit with ${who} is marked completed.`,
            "consultation_completed", {route: "/my-consultations"});
      }
    },
);

// ── 2. Scheduled match-analysis reminders + auto-expiry (spec §6/§7/§9) ──────
exports.matchAnalysisSweep = onSchedule(
    {schedule: "every 30 minutes", timeZone: "Asia/Kolkata"},
    async () => {
      const now = Date.now();
      const qs = await db
          .collection("astrologer_requests")
          .where("type", "==", "matching")
          .where("status", "==", "pending")
          .get();

      for (const doc of qs.docs) {
        const r = doc.data();
        if (r.expired === true) continue;
        const expiresAt = r.expiresAt;
        if (!expiresAt || typeof expiresAt.toMillis !== "function") continue;
        const expiresMs = expiresAt.toMillis();
        const pair =
          `${r.groomProfileName || r.profileAName || "Groom"} × ` +
          `${r.brideProfileName || r.profileBName || "Bride"}`;
        const route = `/match-workspace/${doc.id}`;

        if (now >= expiresMs) {
          // ── Auto-expire (spec §6) ──
          await doc.ref.update({
            expired: true,
            expiredAt: admin.firestore.FieldValue.serverTimestamp(),
            history: admin.firestore.FieldValue.arrayUnion(
                {at: admin.firestore.Timestamp.now(), label: "No response"},
                {at: admin.firestore.Timestamp.now(), label: "Expired"},
            ),
          });
          await notify(
              r.astrologerId,
              "Booking Expired",
              `You did not accept the match analysis for ${pair} in time. ` +
            "It can no longer be accepted.",
              "booking_expired",
              {requestId: doc.id, route},
          );
          await notify(
              r.userId,
              "Astrologer did not respond",
              "The astrologer did not respond within the required time. " +
            "You can choose another astrologer.",
              "booking_expired",
              {requestId: doc.id, route: "/my-analysis"},
          );
          continue;
        }

        // ── Reminders (spec §9) — never ping during 00:00–07:00 IST ──
        if (istHour(now) < 7) continue;
        const remaining = workingMsBetween(now, expiresMs);
        let stage = null;
        if (remaining <= ONE_HOUR && r.remind1Sent !== true) {
          stage = {flag: "remind1Sent", label: "1 Hour Remaining"};
        } else if (remaining <= THREE_HOURS && r.remind3Sent !== true) {
          stage = {flag: "remind3Sent", label: "3 Hours Remaining"};
        } else if (remaining <= SIX_HOURS && r.remind6Sent !== true) {
          stage = {flag: "remind6Sent", label: "6 Hours Remaining"};
        }
        if (!stage) continue;

        await doc.ref.update({[stage.flag]: true});
        await notify(
            r.astrologerId,
            stage.label,
            `${stage.label} to accept the match analysis for ${pair}. ` +
          "Working hours exclude 12 AM – 7 AM.",
            "reminder",
            {requestId: doc.id, route},
        );
      }
    },
);
