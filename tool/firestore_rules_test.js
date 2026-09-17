// Behaviour tests for firestore.rules through the Firebase Rules API
// `projects.test` — the rules are compiled and evaluated on Google's servers
// against the cases below. NOTHING is deployed or released, and no data is
// read or written. Use it where the emulator (Java) is not available.
//
//   firebase login            (once)
//   node tool/firestore_rules_test.js           the repo's firestore.rules
//   node tool/firestore_rules_test.js --live    what the DEPLOYED rules allow
//                                               for the same requests (no
//                                               pass/fail — allowed / denied)
//
// Covers the account-ownership model: role self-promotion, one profile per
// account, the mobile-number registry, removed-login tombstones, admin-assisted
// password reset requests and the backend-only collections.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = execSync('npm root -g').toString().trim();
const auth = require(path.join(root, 'firebase-tools/lib/auth.js'));

const LIVE = process.argv.includes('--live');
const RULES_FILE = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const PROJECT = process.env.FIREBASE_PROJECT || 'matrimony-app-bd0d5';
const D = '/databases/(default)/documents';
const NOW = '2026-09-17T10:00:00Z';
const DAY = Math.floor(Date.parse(NOW) / 86400000);

const token = (provider, email, verified = true) => ({
  firebase: { sign_in_provider: provider },
  ...(email ? { email, email_verified: verified } : {}),
});
const member = (uid, email = '') => ({ uid, token: token('password', email) });
const anon = (uid) => ({ uid, token: token('anonymous') });

const get = (p, data) => ({
  function: 'get',
  args: [{ exactValue: `${D}/${p}` }],
  result: { value: data === null ? null : { data } },
});
const fn = (name, p, value) => ({
  function: name,
  args: [{ exactValue: `${D}/${p}` }],
  result: { value },
});
const userDoc = (uid, role = 'user') => get(`users/${uid}`, { role });

function tc(name, expectation, { authz, method, p, data, existing, mocks = [], live = false }) {
  return {
    name,
    live,
    body: {
      expectation,
      request: {
        auth: authz,
        path: `${D}/${p}`,
        method,
        time: NOW,
        ...(data ? { resource: { data } } : {}),
      },
      ...(existing ? { resource: { data: existing } } : {}),
      functionMocks: mocks,
    },
  };
}

const cases = [
  // ── users: role escalation ──
  tc('member creates own users doc as user', 'ALLOW', {
    authz: member('u1'), method: 'create', p: 'users/u1',
    data: { role: 'user', isBlocked: false, displayName: 'A' },
  }),
  tc('member creates own users doc as ADMIN', 'DENY', {
    authz: member('u1', 'x@gmail.com'), method: 'create', p: 'users/u1',
    data: { role: 'admin', isBlocked: false },
  }),
  tc('member promotes self to admin', 'DENY', {
    authz: member('u1', 'x@gmail.com'), method: 'update', p: 'users/u1',
    existing: { role: 'user', isBlocked: false },
    data: { role: 'admin', isBlocked: false },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('whitelisted verified super admin keeps promotion', 'ALLOW', {
    authz: member('sa', 'sivabeast123123@gmail.com'), method: 'update', p: 'users/sa',
    existing: { role: 'user' }, data: { role: 'super_admin' },
    mocks: [userDoc('sa', 'user')],
  }),
  tc('whitelisted but UNVERIFIED e-mail cannot promote', 'DENY', {
    authz: { uid: 'sa', token: token('password', 'sivabeast123123@gmail.com', false) },
    method: 'update', p: 'users/sa',
    existing: { role: 'user' }, data: { role: 'super_admin' },
    mocks: [userDoc('sa', 'user')],
  }),
  tc('employee role only with registry entry', 'ALLOW', {
    authz: member('e1', 'emp@gmail.com'), method: 'update', p: 'users/e1',
    existing: { role: 'user' }, data: { role: 'astrologer' },
    mocks: [userDoc('e1', 'user'), fn('exists', 'astrology_team/emp@gmail.com', true)],
  }),
  tc('employee role without registry entry', 'DENY', {
    authz: member('e1', 'emp@gmail.com'), method: 'update', p: 'users/e1',
    existing: { role: 'user' }, data: { role: 'astrologer' },
    mocks: [userDoc('e1', 'user'), fn('exists', 'astrology_team/emp@gmail.com', false)],
  }),
  tc('member lifts own suspension', 'DENY', {
    authz: member('u1'), method: 'update', p: 'users/u1',
    existing: { role: 'user', isBlocked: true }, data: { role: 'user', isBlocked: false },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('member undoes Delete Login', 'DENY', {
    authz: member('u1'), method: 'update', p: 'users/u1',
    existing: { role: 'user', authStatus: 'disabled' }, data: { role: 'user' },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('member edits own name and clears mustChangePassword', 'ALLOW', {
    authz: member('u1'), method: 'update', p: 'users/u1',
    existing: { role: 'user', displayName: 'A', mustChangePassword: true },
    data: { role: 'user', displayName: 'B', mustChangePassword: false },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('admin creates users doc for an existing login', 'ALLOW', {
    authz: member('adm'), method: 'create', p: 'users/u9',
    data: { role: 'user', isBlocked: false },
    mocks: [userDoc('adm', 'admin')],
  }),
  tc('admin cannot create an ADMIN users doc for someone else', 'DENY', {
    authz: member('adm'), method: 'create', p: 'users/u9',
    data: { role: 'admin' },
    mocks: [userDoc('adm', 'admin')],
  }),

  // ── profiles: one per account ──
  tc('member creates profile with no ownership record (legacy)', 'ALLOW', {
    authz: member('u1'), method: 'create', p: 'profiles/p1',
    data: newProfile('u1'),
    mocks: [fn('existsAfter', 'profile_owners/u1', false)],
  }),
  tc('member creates profile matching ownership record', 'ALLOW', {
    authz: member('u1'), method: 'create', p: 'profiles/p1',
    data: newProfile('u1'),
    mocks: [
      fn('existsAfter', 'profile_owners/u1', true),
      { function: 'getAfter', args: [{ exactValue: `${D}/profile_owners/u1` }], result: { value: { data: { profileId: 'p1' } } } },
    ],
  }),
  tc('member creates a SECOND profile', 'DENY', {
    authz: member('u1'), method: 'create', p: 'profiles/p2',
    data: newProfile('u1'),
    mocks: [
      fn('existsAfter', 'profile_owners/u1', true),
      { function: 'getAfter', args: [{ exactValue: `${D}/profile_owners/u1` }], result: { value: { data: { profileId: 'p1' } } } },
    ],
  }),
  tc('admin creates a second profile for a member', 'DENY', {
    authz: member('adm'), method: 'create', p: 'profiles/p2',
    data: { userId: 'u1' },
    mocks: [
      userDoc('adm', 'admin'),
      fn('existsAfter', 'profile_owners/u1', true),
      { function: 'getAfter', args: [{ exactValue: `${D}/profile_owners/u1` }], result: { value: { data: { profileId: 'p1' } } } },
    ],
  }),
  tc('admin seeds a dummy profile', 'ALLOW', {
    authz: member('adm'), method: 'create', p: 'profiles/d1',
    data: { userId: 'seed_1', isDummy: true },
    mocks: [userDoc('adm', 'admin')],
  }),
  tc('owner re-homes profile to another uid', 'DENY', {
    authz: member('u1'), method: 'update', p: 'profiles/p1',
    existing: { userId: 'u1', fullName: 'A' }, data: { userId: 'u2', fullName: 'A' },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('owner edits own profile', 'ALLOW', {
    authz: member('u1'), method: 'update', p: 'profiles/p1',
    existing: { userId: 'u1', fullName: 'A' }, data: { userId: 'u1', fullName: 'B' },
    mocks: [userDoc('u1', 'user')],
  }),

  // ── profile_owners ──
  tc('owner re-points record while its profile exists', 'DENY', {
    authz: member('u1'), method: 'update', p: 'profile_owners/u1',
    existing: { userId: 'u1', profileId: 'p1' }, data: { userId: 'u1', profileId: 'p2' },
    mocks: [userDoc('u1', 'user'), fn('existsAfter', 'profiles/p1', true)],
  }),
  tc('owner re-points record after its profile is gone', 'ALLOW', {
    authz: member('u1'), method: 'update', p: 'profile_owners/u1',
    existing: { userId: 'u1', profileId: 'p1' }, data: { userId: 'u1', profileId: 'p2' },
    mocks: [userDoc('u1', 'user'), fn('existsAfter', 'profiles/p1', false)],
  }),
  tc('owner deletes record while profile exists', 'DENY', {
    authz: member('u1'), method: 'delete', p: 'profile_owners/u1',
    existing: { userId: 'u1', profileId: 'p1' },
    mocks: [userDoc('u1', 'user'), fn('existsAfter', 'profiles/p1', true)],
  }),
  tc('another member writes my ownership record', 'DENY', {
    authz: member('u2'), method: 'create', p: 'profile_owners/u1',
    data: { userId: 'u1', profileId: 'px' },
    mocks: [userDoc('u2', 'user')],
  }),

  // ── login_index ──
  tc('member claims a free number for self', 'ALLOW', {
    authz: member('u1'), method: 'create', p: 'login_index/9876543210',
    data: { uid: 'u1', authEmail: 'p9876543210@phone.jothidamatrimony.app' },
  }),
  tc('member claims a number for someone else', 'DENY', {
    authz: member('u1'), method: 'create', p: 'login_index/9876543210',
    data: { uid: 'u2', authEmail: 'x@y.com' },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('member takes over a number held by another uid', 'DENY', {
    authz: member('u1'), method: 'update', p: 'login_index/9876543210',
    existing: { uid: 'u2', authEmail: 'a@b.com' }, data: { uid: 'u1', authEmail: 'c@d.com' },
    mocks: [userDoc('u1', 'user')],
  }),
  tc('admin restores a number for a member', 'ALLOW', {
    authz: member('adm'), method: 'create', p: 'login_index/9876543210',
    data: { uid: 'u2', authEmail: 'p9876543210@phone.jothidamatrimony.app' },
    mocks: [userDoc('adm', 'admin')],
  }),
  tc('anyone reads the registry', 'ALLOW', {
    authz: null, method: 'get', p: 'login_index/9876543210',
    existing: { uid: 'u2', authEmail: 'a@b.com' },
  }),

  // ── tombstones ──
  tc('account reads its own tombstone at sign-in', 'ALLOW', {
    authz: member('u1'), method: 'get', p: 'login_tombstones/u1',
    existing: { mode: 'deleted' },
  }),
  tc('another member reads a tombstone', 'DENY', {
    authz: member('u2'), method: 'get', p: 'login_tombstones/u1',
    existing: { mode: 'deleted' }, mocks: [userDoc('u2', 'user')],
  }),
  tc('account deletes its own tombstone', 'DENY', {
    authz: member('u1'), method: 'delete', p: 'login_tombstones/u1',
    existing: { mode: 'disabled' }, mocks: [userDoc('u1', 'user')],
  }),

  // ── password reset requests ──
  tc('guest files a valid reset request', 'ALLOW', {
    authz: anon('g1'), method: 'create', p: `password_reset_requests/9876543210_${DAY}`,
    data: { mobile: '9876543210', name: 'Ravi', description: 'Forgot', status: 'pending', createdAt: NOW, createdByUid: 'g1', dayKey: DAY, source: 'app' },
  }),
  tc('request carrying a password field', 'DENY', {
    authz: anon('g1'), method: 'create', p: `password_reset_requests/9876543210_${DAY}`,
    data: { mobile: '9876543210', status: 'pending', createdAt: NOW, createdByUid: 'g1', dayKey: DAY, password: 'secret' },
  }),
  tc('request with a forged id (another day)', 'DENY', {
    authz: anon('g1'), method: 'create', p: `password_reset_requests/9876543210_${DAY - 5}`,
    data: { mobile: '9876543210', status: 'pending', createdAt: NOW, createdByUid: 'g1', dayKey: DAY - 5 },
  }),
  tc('request pre-marked resolved', 'DENY', {
    authz: anon('g1'), method: 'create', p: `password_reset_requests/9876543210_${DAY}`,
    data: { mobile: '9876543210', status: 'resolved', createdAt: NOW, createdByUid: 'g1', dayKey: DAY },
  }),
  tc('requester overwrites a request (second one the same day)', 'DENY', {
    authz: anon('g1'), method: 'update', p: `password_reset_requests/9876543210_${DAY}`,
    existing: { mobile: '9876543210', status: 'pending', createdByUid: 'g1' },
    data: { mobile: '9876543210', status: 'pending', createdByUid: 'g1', description: 'again' },
    mocks: [fn('get', 'users/g1', null)],
  }),
  tc('member lists other people\'s requests', 'DENY', {
    authz: member('u5'), method: 'get', p: `password_reset_requests/9876543210_${DAY}`,
    existing: { mobile: '9876543210', createdByUid: 'g1' },
    mocks: [userDoc('u5', 'user')],
  }),
  tc('admin resolves a request', 'ALLOW', {
    authz: member('adm'), method: 'update', p: `password_reset_requests/9876543210_${DAY}`,
    existing: { status: 'pending' }, data: { status: 'resolved' },
    mocks: [userDoc('adm', 'admin')],
  }),

  // ── server-only ──
  tc('client reads rate-limit windows', 'DENY', {
    authz: member('adm'), method: 'get', p: 'auth_rate_limits/x',
    existing: { count: 1 }, mocks: [userDoc('adm', 'admin')],
  }),
  tc('client forges a recovery session', 'DENY', {
    authz: member('u1'), method: 'create', p: 'auth_recovery_sessions/u1_1',
    data: { uid: 'u1' },
  }),

  // ── PROFILE CREATION (the permission-denied report) ──────────────────────
  // The exact writes FirestoreService.createProfile + submitProfile make.
  ...profileCreationCases(),
];

function newProfile(uid, extra = {}) {
  return {
    userId: uid, fullName: 'Ravi Kumar', gender: 'Male', dateOfBirth: '1995-01-01T00:00:00Z',
    religion: 'Hindu', city: 'Madurai', status: 'pending', isActive: true,
    isVerified: false, isDummy: false, reportCount: 0, viewCount: 0, interestCount: 0,
    privacySettings: { photo: true }, contactPrivacy: 'private', ...extra,
  };
}
function noClaim(uid) { return fn('existsAfter', `profile_owners/${uid}`, false); }
function google(uid) { return { uid, token: token('google.com', `${uid}@gmail.com`) }; }

function profileCreationCases() {
  return [
    tc('[1] newly registered member creates own profile', 'ALLOW', {
      authz: member('new1'), method: 'create', p: 'profiles/pNew1',
      data: newProfile('new1'), mocks: [noClaim('new1')], live: true,
    }),
    tc('[2] Google-signed-in member creates own profile', 'ALLOW', {
      authz: google('g1'), method: 'create', p: 'profiles/pG1',
      data: newProfile('g1'), mocks: [noClaim('g1')], live: true,
    }),
    tc('[2] member queries their own profiles (before creating)', 'ALLOW', {
      authz: member('new1'), method: 'get', p: 'profiles/pOld',
      existing: newProfile('new1'), live: true,
    }),
    tc('[2] member writes the private copy of hidden fields', 'ALLOW', {
      authz: member('new1'), method: 'create', p: 'profile_private/new1',
      data: { userId: 'new1', profileId: 'pNew1', profilePhotoUrl: 'x' }, live: true,
    }),
    tc('[2] member writes their contact record', 'ALLOW', {
      authz: member('new1'), method: 'create', p: 'contacts/new1',
      data: { userId: 'new1', profileId: 'pNew1', mobileNumber: '' }, live: true,
    }),
    tc('[2] member marks their account profile-complete', 'ALLOW', {
      authz: member('new1'), method: 'update', p: 'users/new1',
      existing: { role: 'user', isProfileComplete: false },
      data: { role: 'user', isProfileComplete: true, profileCompleted: true },
      mocks: [userDoc('new1', 'user')], live: true,
    }),
    tc('[3] member creates a profile for ANOTHER user', 'DENY', {
      authz: member('u1'), method: 'create', p: 'profiles/pX',
      data: newProfile('victim'), mocks: [userDoc('u1', 'user'), noClaim('victim')], live: true,
    }),
    tc('[3] member edits ANOTHER user\'s profile', 'DENY', {
      authz: member('u1'), method: 'update', p: 'profiles/pV',
      existing: newProfile('victim'), data: newProfile('victim', { fullName: 'Hacked' }),
      mocks: [userDoc('u1', 'user')], live: true,
    }),
    tc('[3] member writes ANOTHER user\'s private copy', 'DENY', {
      authz: member('u1'), method: 'create', p: 'profile_private/victim',
      data: { userId: 'victim' }, mocks: [userDoc('u1', 'user')],
    }),
    tc('[4] existing member edits own profile', 'ALLOW', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1', { status: 'approved' }),
      data: newProfile('m1', { status: 'approved', aboutMe: 'Updated' }),
      mocks: [userDoc('m1', 'user')], live: true,
    }),
    tc('[4] member re-creates a profile (approved → pending review)', 'ALLOW', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1', { status: 'approved', isVerified: true }),
      data: newProfile('m1'), mocks: [userDoc('m1', 'user')], live: true,
    }),
    tc('[4] member marks themself married', 'ALLOW', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1', { status: 'approved' }),
      data: newProfile('m1', { status: 'approved', isMarried: true, isActive: false }),
      mocks: [userDoc('m1', 'user')], live: true,
    }),
    tc('[4] member approves their own profile', 'DENY', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1'), data: newProfile('m1', { status: 'approved' }),
      mocks: [userDoc('m1', 'user')],
    }),
    tc('[4] member marks their own profile verified', 'DENY', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1'), data: newProfile('m1', { profileVerified: true }),
      mocks: [userDoc('m1', 'user')],
    }),
    tc('[4] a BLOCKED member re-opens their profile for review', 'DENY', {
      authz: member('m1'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1', { status: 'blocked', isActive: false }),
      data: newProfile('m1'), mocks: [userDoc('m1', 'user')],
    }),
    tc('[5] admin views a member profile', 'ALLOW', {
      authz: member('adm'), method: 'get', p: 'profiles/pM1',
      existing: newProfile('m1', { status: 'pending' }), mocks: [userDoc('adm', 'admin')], live: true,
    }),
    tc('[5] admin edits and approves a member profile', 'ALLOW', {
      authz: member('adm'), method: 'update', p: 'profiles/pM1',
      existing: newProfile('m1'), data: newProfile('m1', { status: 'approved', fullName: 'Fixed' }),
      mocks: [userDoc('adm', 'admin')], live: true,
    }),
    tc('[5] admin creates a profile for a member', 'ALLOW', {
      authz: member('adm'), method: 'create', p: 'profiles/pA1',
      data: newProfile('m9', { status: 'approved' }),
      mocks: [userDoc('adm', 'admin'), noClaim('m9')], live: true,
    }),
    tc('[5] admin reads a member\'s private copy', 'ALLOW', {
      authz: member('adm'), method: 'get', p: 'profile_private/m1',
      existing: { userId: 'm1' }, mocks: [userDoc('adm', 'admin')],
    }),
    tc('[6] signed-out request creates a profile', 'DENY', {
      authz: null, method: 'create', p: 'profiles/pAnon',
      data: newProfile('nobody'), live: true,
    }),
    tc('[6] guest (anonymous) session creates a profile', 'DENY', {
      authz: anon('guest1'), method: 'create', p: 'profiles/pGuest',
      data: newProfile('guest1'), mocks: [noClaim('guest1')], live: true,
    }),
    tc('[7] profile without a name', 'DENY', {
      authz: member('new2'), method: 'create', p: 'profiles/pNoName',
      data: newProfile('new2', { fullName: '' }), mocks: [noClaim('new2')],
    }),
    tc('[7] profile without a gender', 'DENY', {
      authz: member('new2'), method: 'create', p: 'profiles/pNoGender',
      data: (() => { const d = newProfile('new2'); delete d.gender; return d; })(),
      mocks: [noClaim('new2')],
    }),
    tc('[7] profile whose owner is not a string', 'DENY', {
      authz: member('new2'), method: 'create', p: 'profiles/pBadOwner',
      data: newProfile('new2', { userId: 123 }), mocks: [noClaim('new2')],
    }),
    tc('[7] member creates an already-approved profile', 'DENY', {
      authz: member('new2'), method: 'create', p: 'profiles/pSelfApproved',
      data: newProfile('new2', { status: 'approved' }), mocks: [noClaim('new2')],
    }),
    tc('[7] member creates a test (dummy) profile', 'DENY', {
      authz: member('new2'), method: 'create', p: 'profiles/pDummy',
      data: newProfile('new2', { isDummy: true }), mocks: [noClaim('new2')],
    }),
    tc('[9] employee reads a member\'s private copy for a report', 'ALLOW', {
      authz: member('emp', 'emp@gmail.com'), method: 'get', p: 'profile_private/m1',
      existing: { userId: 'm1' }, mocks: [userDoc('emp', 'astrologer')],
    }),
    tc('[9] employee cannot browse account records', 'DENY', {
      authz: member('emp', 'emp@gmail.com'), method: 'get', p: 'users/m1',
      existing: { role: 'user' }, mocks: [userDoc('emp', 'astrologer')], live: true,
    }),
    tc('[9] member files a horoscope report request', 'ALLOW', {
      authz: member('m1'), method: 'create', p: 'astrologer_requests/r1',
      data: { userId: 'm1', type: 'matching', paid: true, amount: 199, paymentId: 'GPA.1234-5678', status: 'pending' },
      live: true,
    }),
    tc('[9] assigned employee updates the request', 'ALLOW', {
      authz: member('emp', 'emp@gmail.com'), method: 'update', p: 'astrologer_requests/r1',
      existing: { userId: 'm1', astrologerId: 'emp', astrologerEmail: 'emp@gmail.com', status: 'accepted' },
      data: { userId: 'm1', astrologerId: 'emp', astrologerEmail: 'emp@gmail.com', status: 'completed' },
      live: true,
    }),
  ];
}

(async () => {
  const acct = auth.getGlobalDefaultAccount();
  const at = await auth.getAccessToken(acct.tokens.refresh_token, []);
  const token = at.access_token || at;
  let RULES = RULES_FILE;
  let run = cases;
  if (LIVE) {
    const h = { Authorization: `Bearer ${token}` };
    const base = `https://firebaserules.googleapis.com/v1/projects/${PROJECT}`;
    const rel = await (await fetch(`${base}/releases/cloud.firestore`, { headers: h })).json();
    const rs = await (await fetch(`https://firebaserules.googleapis.com/v1/${rel.rulesetName}`, { headers: h })).json();
    RULES = rs.source.files[0].content;
    console.log(`LIVE ruleset ${rel.rulesetName.split('/').pop()} (released ${rel.updateTime})\n`);
    // Every case asks "is it allowed?" — the answer is reported, not judged.
    run = cases.filter((c) => c.live).map((c) => ({ ...c, body: { ...c.body, expectation: 'ALLOW' } }));
  }
  const res = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT}:test`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: { files: [{ name: 'firestore.rules', content: RULES }] },
        testSuite: { testCases: run.map((c) => c.body) },
      }),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    console.log('HTTP', res.status, JSON.stringify(json).slice(0, 2000));
    process.exit(2);
  }
  if (json.issues) console.log('ISSUES', JSON.stringify(json.issues, null, 1));
  let pass = 0;
  let fail = 0;
  if (LIVE) {
    (json.testResults || []).forEach((r, i) => {
      const expected = cases.find((c) => c.name === run[i].name).body.expectation;
      const got = r.state === 'SUCCESS' ? 'ALLOW' : 'DENY';
      console.log(`${got === 'ALLOW' ? 'allowed' : 'DENIED '}  ${got === expected ? '     ' : '(!)  '}${run[i].name}`);
    });
    console.log('\n(!) = the deployed rules answer differently from the repo rules.');
    process.exit(0);
  }
  (json.testResults || []).forEach((r, i) => {
    const ok = r.state === 'SUCCESS';
    ok ? pass++ : fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  [${run[i].body.expectation}] ${run[i].name}`);
    if (!ok) console.log('      ', JSON.stringify(r.debugMessages || r.errorPosition || r).slice(0, 600));
  });
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
