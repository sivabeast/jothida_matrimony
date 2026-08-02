# Push Notifications — Setup & Deploy Guide

The notification pipeline is live in `functions/index.js`. This doc explains
what runs where and exactly what YOU must deploy.

## Architecture (one-page)

```
Event                        Firestore write                    Push
─────────────────────────────────────────────────────────────────────────────
Interest sent          →  notifications/interest_received_{id}   ─┐
Interest accepted      →  notifications/interest_accepted_{id}    ├─ onNotificationCreated
Interest rejected      →  notifications/interest_rejected_{id}    │  (single push gate —
Report ready / appt /  →  notifications/{auto id}                 │  pushes every doc
admin update (client)                                            ─┘  without pushed:true)
Chat message           →  notifications/chat_{thread}_{uid}     onChatMessageCreated pushes
                          (upserted, pushed:true)                itself (skips when receiver
                                                                 is viewing the thread)
New matching profile   →  notifications/new_profile_{pid}_{uid} onProfileWritten pushes per
                          (pushed:true)                          user (preference-matched)
Announcement           →  announcements/{id} only               onAnnouncementCreated →
                                                                 topic 'users'/'employees'
Interest withdrawn     →  deletes interest_* notification docs  (no push)
Interest accepted      →  onInterestWritten ALSO guarantees chats/{a_b} + greeting
                          (safety net — client normally creates both instantly)
```

- **Exactly-once pushes**: deterministic notification doc ids + the
  `onDocumentCreated` gate. A doc `set()` by both client and server still only
  fires ONE create event.
- **Deep links**: every push carries `data.route`; the app navigates directly
  (foreground banner "View", background/terminated tap, cold start replay
  after auth resolves). There is no notification-details page.
- **Invalid tokens**: any send that fails with
  `registration-token-not-registered` / `invalid-registration-token` deletes
  `users/{uid}.fcmToken` automatically.
- **Token freshness**: the app registers the token at login, at app start for
  an existing session, and on every `onTokenRefresh`.
- **Topics**: at token registration the app subscribes the device to `users`
  (role user) or `employees` (role astrologer) for announcement broadcasts.

## What YOU must do (in order)

1. **Blaze plan** — Firestore-triggered v2 functions require the Blaze plan on
   the Firebase project.
2. **Enable APIs** (first v2 trigger deploy usually prompts for these):
   Cloud Functions, Cloud Build, Artifact Registry, Eventarc, Cloud Run.
3. **Deploy everything**:
   ```bash
   firebase deploy --only functions,firestore:rules,firestore:indexes
   ```
   Rules now also enforce duplicate-interest prevention and the `admin_logs`
   collection, and the indexes file adds the `notifications(userId, createdAt)`
   composite the notification stream needs.
4. **Verify** in the Firebase console → Functions: you should see
   `onNotificationCreated`, `onInterestWritten`, `onChatMessageCreated`,
   `onProfileWritten`, `onAnnouncementCreated` (+ the two existing callables).

## Testing checklist (two phones / one phone + emulator)

| Event | Expect |
|---|---|
| A sends interest to B (B app killed) | Tray push "New Interest 💌" → tap opens Interests → Received with A highlighted |
| B accepts (A backgrounded) | Push "Interest Accepted 🎉" → tap opens Interests → Accepted with B highlighted; chat exists with greeting |
| A chats B (B not in that chat) | Push "New Message 💬" → tap opens that conversation |
| A chats B (B viewing that chat) | NO push |
| Admin approves a pending profile | Member gets "Profile Approved ✅" push |
| New profile approved | Only preference-matching members get "New Matching Profile ✨" |
| Admin creates announcement | All members get the broadcast → tap opens the announcement screen |

Test each of: app open (in-app banner), backgrounded (tray), killed (tray →
cold-start deep link), locked screen.

## Notes

- Android 13+ runtime notification permission is requested at app start
  (`POST_NOTIFICATIONS` is declared in the manifest).
- Foreground pushes show an in-app banner with a "View" action (the OS tray is
  used only when the app is not in the foreground).
- There is no membership/subscription system, so no expiry-reminder scheduler
  is deployed.
