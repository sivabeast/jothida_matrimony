// Behaviour tests for firestore.rules through the Firebase Rules API
// `projects.test` — the rules are compiled and evaluated on Google's servers
// against the cases below. NOTHING is deployed or released, and no data is
// read or written. Use it where the emulator (Java) is not available.
//
//   firebase login            (once)
//   node tool/firestore_rules_test.js
//
// Covers the account-ownership model: role self-promotion, one profile per
// account, the mobile-number registry, removed-login tombstones, admin-assisted
// password reset requests and the backend-only collections.
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = execSync('npm root -g').toString().trim();
const auth = require(path.join(root, 'firebase-tools/lib/auth.js'));

const RULES = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
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

function tc(name, expectation, { authz, method, p, data, existing, mocks = [] }) {
  return {
    name,
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
    data: { userId: 'u1' },
    mocks: [fn('existsAfter', 'profile_owners/u1', false)],
  }),
  tc('member creates profile matching ownership record', 'ALLOW', {
    authz: member('u1'), method: 'create', p: 'profiles/p1',
    data: { userId: 'u1' },
    mocks: [
      fn('existsAfter', 'profile_owners/u1', true),
      { function: 'getAfter', args: [{ exactValue: `${D}/profile_owners/u1` }], result: { value: { data: { profileId: 'p1' } } } },
    ],
  }),
  tc('member creates a SECOND profile', 'DENY', {
    authz: member('u1'), method: 'create', p: 'profiles/p2',
    data: { userId: 'u1' },
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
];

(async () => {
  const acct = auth.getGlobalDefaultAccount();
  const at = await auth.getAccessToken(acct.tokens.refresh_token, []);
  const token = at.access_token || at;
  const res = await fetch(
    `https://firebaserules.googleapis.com/v1/projects/${PROJECT}:test`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        source: { files: [{ name: 'firestore.rules', content: RULES }] },
        testSuite: { testCases: cases.map((c) => c.body) },
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
  (json.testResults || []).forEach((r, i) => {
    const ok = r.state === 'SUCCESS';
    ok ? pass++ : fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  [${cases[i].body.expectation}] ${cases[i].name}`);
    if (!ok) console.log('      ', JSON.stringify(r.debugMessages || r.errorPosition || r).slice(0, 600));
  });
  console.log(`\n${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
})();
