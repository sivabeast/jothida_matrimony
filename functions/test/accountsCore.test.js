// Run with:  node --test functions/test/accountsCore.test.js
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../accountsCore');

test('localMobile accepts Indian mobiles in every typed form', () => {
  assert.equal(core.localMobile('9876543210'), '9876543210');
  assert.equal(core.localMobile('+91 98765 43210'), '9876543210');
  assert.equal(core.localMobile('0091 9876543210'), '9876543210');
  assert.equal(core.localMobile('09876543210'), '9876543210');
  assert.equal(core.localMobile('+1 415 555 01234'), '');
  assert.equal(core.localMobile('98765'), '');
  assert.equal(core.localMobile('9876543210@gmail.com'), '');
});

test('synthesized phone address round-trips', () => {
  assert.equal(core.phoneAuthEmail('+919876543210'), 'p9876543210@phone.jothidamatrimony.app');
  assert.ok(core.isPhoneAuthEmail('P9876543210@PHONE.jothidamatrimony.app'));
  assert.ok(!core.isPhoneAuthEmail('someone@gmail.com'));
});

test('provision input is validated on the server', () => {
  assert.equal(core.validateProvisionInput({ mobile: '12', password: 'secret1' }).ok, false);
  assert.equal(core.validateProvisionInput({ mobile: '9876543210', password: '123' }).ok, false);
  assert.equal(
    core.validateProvisionInput({ mobile: '9876543210', password: 'secret1', email: 'bad@' }).ok,
    false,
  );
  // The synthesized address can never be passed off as a real e-mail.
  assert.equal(
    core.validateProvisionInput({
      mobile: '9876543210',
      password: 'secret1',
      email: 'p9876543210@phone.jothidamatrimony.app',
    }).ok,
    false,
  );
  const ok = core.validateProvisionInput({ mobile: '+91 98765 43210', password: 'secret1' });
  assert.equal(ok.ok, true);
  assert.equal(ok.value.authEmail, 'p9876543210@phone.jothidamatrimony.app');
  const withEmail = core.validateProvisionInput({
    mobile: '9876543210',
    password: 'secret1',
    email: ' Ravi@Example.com ',
  });
  assert.equal(withEmail.value.authEmail, 'ravi@example.com');
});

test('an Auth record is only replaced when named AND nothing belongs to it', () => {
  const base = { requestedUid: 'u1', authUid: 'u1', hasUserDoc: false, profileCount: 0 };
  assert.equal(core.isReplaceableOrphan(base), true);
  assert.equal(core.isReplaceableOrphan({ ...base, requestedUid: '' }), false);
  assert.equal(core.isReplaceableOrphan({ ...base, requestedUid: 'u2' }), false);
  assert.equal(core.isReplaceableOrphan({ ...base, profileCount: 1 }), false);
  assert.equal(core.isReplaceableOrphan({ ...base, hasUserDoc: true }), false);
  assert.equal(
    core.isReplaceableOrphan({ ...base, hasUserDoc: true, userAuthStatus: 'deleted' }),
    true,
  );
});

test('temporary passwords satisfy the policy and avoid look-alikes', () => {
  for (let i = 0; i < 50; i++) {
    const p = core.temporaryPassword();
    assert.equal(core.passwordProblem(p), '');
    assert.ok(!/[01OIl]/.test(p), p);
  }
});

test('masking never reveals the synthesized address', () => {
  assert.equal(core.maskEmail('p9876543210@phone.jothidamatrimony.app'), '');
  assert.equal(core.maskEmail('ravi.kumar@gmail.com'), 'ra•••@g•••.com');
  assert.equal(core.maskName('Ravi Kumar'), 'R••• K••••');
});

test('recovery never picks between two matrimony profiles', () => {
  const r = core.recoveryCandidates(
    [
      { uid: 'a', email: 'pa@x.app', providers: ['password'], hasUserDoc: true, profileCount: 1 },
      { uid: 'b', email: 'b@x.com', providers: ['password'], hasUserDoc: true, profileCount: 1 },
    ],
    'session',
  );
  assert.equal(r.status, 'multiple-profiles');
});

test('recovery lets the member choose between login identities of ONE profile', () => {
  const r = core.recoveryCandidates(
    [
      { uid: 'a', email: 'pa@x.app', providers: ['password'], hasUserDoc: true, profileCount: 1 },
      { uid: 'b', email: 'b@x.com', providers: ['password'], hasUserDoc: true, profileCount: 0 },
    ],
    'session',
  );
  assert.equal(r.status, 'select');
  assert.equal(r.accounts.length, 2);
});

test('the throwaway OTP identity and password-less accounts are never candidates', () => {
  const r = core.recoveryCandidates(
    [
      { uid: 'session', email: '', providers: ['phone'], hasUserDoc: false, profileCount: 0 },
      { uid: 'g', email: '', providers: ['google.com'], hasUserDoc: true, profileCount: 1 },
      { uid: 'a', email: 'pa@x.app', providers: ['password'], hasUserDoc: true, profileCount: 1 },
      { uid: 'a', email: 'pa@x.app', providers: ['password'], hasUserDoc: true, profileCount: 1 },
    ],
    'session',
  );
  assert.equal(r.status, 'single');
  assert.equal(r.accounts[0].uid, 'a');
  assert.equal(core.recoveryCandidates([], 'session').status, 'none');
});

test('an OTP session must be a fresh phone session for the same number', () => {
  const now = 1_800_000_000;
  const token = { firebase: { sign_in_provider: 'phone' }, phone_number: '+919876543210', auth_time: now - 60 };
  assert.equal(core.otpSessionProblem(token, '9876543210', now), '');
  assert.equal(core.otpSessionProblem(null, '9876543210', now), 'unauthenticated');
  assert.equal(
    core.otpSessionProblem({ ...token, firebase: { sign_in_provider: 'password' } }, '9876543210', now),
    'not-phone-session',
  );
  assert.equal(core.otpSessionProblem(token, '9123456789', now), 'number-mismatch');
  assert.equal(
    core.otpSessionProblem({ ...token, auth_time: now - core.OTP_SESSION_MAX_AGE_SECONDS - 1 }, '9876543210', now),
    'otp-expired',
  );
});

test('fixed-window rate limit', () => {
  let state = null;
  const t0 = 1_000_000;
  for (let i = 0; i < 3; i++) {
    const step = core.rateLimitStep(state, t0 + i, 60_000, 3);
    assert.equal(step.allowed, true);
    state = step.next;
  }
  assert.equal(core.rateLimitStep(state, t0 + 10, 60_000, 3).allowed, false);
  assert.equal(core.rateLimitStep(state, t0 + 60_000, 60_000, 3).allowed, true);
});

test('account refs are opaque and bound to the OTP session', () => {
  const a = core.accountRef('uid1', 'sess', 100);
  assert.notEqual(a, core.accountRef('uid1', 'sess', 101));
  assert.ok(!a.includes('uid1'));
});
