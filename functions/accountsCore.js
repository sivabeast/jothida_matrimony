/**
 * Pure helpers behind the account-management functions (accounts.js).
 *
 * No Firebase imports here, so every rule the backend enforces — input
 * validation, which accounts a verified phone number may reset, what counts as
 * a stale login — is covered by `node --test functions/test`.
 *
 * Mirrors lib/core/utils/login_identifier.dart and account_identity.dart in the
 * app. Change a rule in both places.
 */
'use strict';

const crypto = require('crypto');

/** Domain of the synthesized, non-deliverable sign-in address of phone-only accounts. */
const PHONE_EMAIL_DOMAIN = 'phone.jothidamatrimony.app';

/** App password policy (Validators.password): at least 6 characters. */
const MIN_PASSWORD_LENGTH = 6;
const MAX_PASSWORD_LENGTH = 128;

/** An OTP session older than this cannot reset a password. */
const OTP_SESSION_MAX_AGE_SECONDS = 10 * 60;

const ADMIN_ROLES = ['admin', 'super_admin'];

/**
 * The 10-digit local mobile number in `raw`, or '' when it is not one.
 * Exactly `LoginIdentifier.localMobile` + `normalizeIndianPhone` in the app.
 */
function localMobile(raw) {
  const value = String(raw == null ? '' : raw).trim();
  if (!value || value.includes('@')) return '';
  let digits = value.replace(/[^0-9]/g, '');
  if (!digits) return '';
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith('0')) digits = digits.slice(1);
  if (digits.length === 10) return digits;
  if (digits.length === 12 && digits.startsWith('91')) return digits.slice(2);
  return '';
}

function phoneAuthEmail(mobile) {
  return `p${localMobile(mobile)}@${PHONE_EMAIL_DOMAIN}`;
}

function isPhoneAuthEmail(email) {
  return String(email || '').trim().toLowerCase().endsWith(`@${PHONE_EMAIL_DOMAIN}`);
}

const EMAIL_RE = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

function normalizeEmail(raw) {
  const email = String(raw == null ? '' : raw).trim().toLowerCase();
  return email;
}

function isValidEmail(email) {
  return EMAIL_RE.test(String(email || ''));
}

/** Returns an error message, or '' when the password is acceptable. */
function passwordProblem(password) {
  if (typeof password !== 'string') return 'A password is required.';
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Password must be at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (password.length > MAX_PASSWORD_LENGTH) {
    return `Password must be at most ${MAX_PASSWORD_LENGTH} characters.`;
  }
  return '';
}

/**
 * Validates the admin "create / restore login" input. Returns
 * `{ ok: true, value }` or `{ ok: false, message }`.
 */
function validateProvisionInput(data) {
  const d = data || {};
  const mobile = localMobile(d.mobile);
  if (!mobile) return { ok: false, message: 'Enter a valid 10-digit mobile number.' };
  const email = normalizeEmail(d.email);
  if (email && (!isValidEmail(email) || isPhoneAuthEmail(email))) {
    return { ok: false, message: 'Enter a valid e-mail address, or leave it empty.' };
  }
  const problem = passwordProblem(d.password);
  if (problem) return { ok: false, message: problem };
  const displayName = String(d.displayName || '').trim().slice(0, 100);
  const gender = String(d.gender || '').trim().slice(0, 20);
  const targetUid = String(d.targetUid || '').trim();
  if (targetUid && !/^[A-Za-z0-9_-]{6,128}$/.test(targetUid)) {
    return { ok: false, message: 'Invalid account id.' };
  }
  const replaceOrphanUid = String(d.replaceOrphanUid || '').trim();
  return {
    ok: true,
    value: {
      mobile,
      email,
      authEmail: email || phoneAuthEmail(mobile),
      password: d.password,
      displayName,
      gender,
      targetUid,
      replaceOrphanUid,
      profileCreated: d.profileCreated === true,
      mustChangePassword: d.mustChangePassword === true,
    },
  };
}

/**
 * Whether an existing Firebase Auth record may be DELETED to make room for a
 * new login — only when an admin explicitly named it AND nothing in the app
 * still belongs to it.
 */
function isReplaceableOrphan({ requestedUid, authUid, hasUserDoc, userAuthStatus, profileCount, tombstoneMode }) {
  if (!requestedUid || requestedUid !== authUid) return false;
  if (profileCount > 0) return false;
  if (!hasUserDoc) return true;
  return userAuthStatus === 'deleted' || userAuthStatus === 'disabled' || tombstoneMode === 'deleted';
}

/** Random temporary password without look-alike characters (0/O, 1/l/I). */
function temporaryPassword(length = 10) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < length; i++) out += alphabet[crypto.randomInt(alphabet.length)];
  return out;
}

/** `ra•••@g•••.com` — never the synthesized phone address. */
function maskEmail(raw) {
  const email = normalizeEmail(raw);
  if (!email || isPhoneAuthEmail(email)) return '';
  const at = email.indexOf('@');
  if (at <= 0) return '';
  const local = email.slice(0, at);
  const domain = email.slice(at + 1);
  const dot = domain.lastIndexOf('.');
  const host = dot > 0 ? domain.slice(0, dot) : domain;
  const tld = dot > 0 ? domain.slice(dot) : '';
  const part = (s, keep) => (s.length <= keep ? `${s.slice(0, 1)}•••` : `${s.slice(0, keep)}•••`);
  return `${part(local, 2)}@${part(host, 1)}${tld}`;
}

function maskName(raw) {
  const name = String(raw || '').trim();
  if (!name) return '';
  return name
    .split(/\s+/)
    .map((w) => (w.length <= 1 ? w : `${w[0]}${'•'.repeat(Math.min(w.length - 1, 4))}`))
    .join(' ');
}

/** Opaque, session-bound reference for a candidate account — never the uid. */
function accountRef(uid, sessionUid, authTime) {
  return crypto
    .createHash('sha256')
    .update(`${uid}:${sessionUid}:${authTime}`)
    .digest('hex')
    .slice(0, 24);
}

/**
 * Which password accounts a VERIFIED phone number may reset.
 *
 * `candidates`: [{ uid, email, providers, hasUserDoc, profileCount, displayName }]
 * gathered from the phone registry, the synthesized address, the users whose
 * mobile matches, and the OTP identity itself. `sessionUid` is that OTP
 * identity.
 *
 * Only accounts that actually have a password credential are resettable. A
 * throwaway OTP identity (no account record) is never a candidate.
 *
 * Returns `{ status, accounts }` where status is:
 *   'none'              — nothing to reset (member is sent to the admin);
 *   'multiple-profiles' — the number belongs to more than one matrimony
 *                         profile: refuse and flag for the admin, never pick;
 *   'select'            — several login identities, one profile at most: the
 *                         member chooses from masked entries;
 *   'single'            — exactly one account.
 */
function recoveryCandidates(candidates, sessionUid) {
  const byUid = new Map();
  for (const c of candidates || []) {
    if (!c || !c.uid) continue;
    if (c.uid === sessionUid && !c.hasUserDoc) continue; // throwaway OTP identity
    const hasPassword = (c.providers || []).includes('password') || !!c.email;
    if (!hasPassword) continue;
    const prev = byUid.get(c.uid);
    byUid.set(c.uid, prev ? { ...prev, ...c } : c);
  }
  const accounts = [...byUid.values()];
  if (accounts.length === 0) return { status: 'none', accounts };
  const withProfile = accounts.filter((a) => (a.profileCount || 0) > 0);
  if (withProfile.length > 1 || withProfile.some((a) => a.profileCount > 1)) {
    return { status: 'multiple-profiles', accounts };
  }
  return { status: accounts.length === 1 ? 'single' : 'select', accounts };
}

/** The OTP session may reset a password: phone provider, fresh, number matches. */
function otpSessionProblem(token, requestedMobile, nowSeconds) {
  if (!token) return 'unauthenticated';
  const provider = token.firebase && token.firebase.sign_in_provider;
  if (provider !== 'phone') return 'not-phone-session';
  const verified = localMobile(token.phone_number);
  if (!verified || verified !== localMobile(requestedMobile)) return 'number-mismatch';
  const authTime = Number(token.auth_time || 0);
  if (!authTime || nowSeconds - authTime > OTP_SESSION_MAX_AGE_SECONDS) return 'otp-expired';
  return '';
}

/**
 * Fixed-window rate limit decision. `state` is the stored `{ windowStart, count }`
 * (or null). Returns `{ allowed, next }` — `next` is what to store.
 */
function rateLimitStep(state, nowMs, windowMs, max) {
  if (!state || typeof state.windowStart !== 'number' || nowMs - state.windowStart >= windowMs) {
    return { allowed: true, next: { windowStart: nowMs, count: 1 } };
  }
  if ((state.count || 0) >= max) return { allowed: false, next: state };
  return { allowed: true, next: { windowStart: state.windowStart, count: (state.count || 0) + 1 } };
}

/** Day number used in password_reset_requests ids (UTC days since epoch). */
function dayKey(nowMs) {
  return Math.floor(nowMs / 86400000);
}

module.exports = {
  PHONE_EMAIL_DOMAIN,
  MIN_PASSWORD_LENGTH,
  MAX_PASSWORD_LENGTH,
  OTP_SESSION_MAX_AGE_SECONDS,
  ADMIN_ROLES,
  localMobile,
  phoneAuthEmail,
  isPhoneAuthEmail,
  normalizeEmail,
  isValidEmail,
  passwordProblem,
  validateProvisionInput,
  isReplaceableOrphan,
  temporaryPassword,
  maskEmail,
  maskName,
  accountRef,
  recoveryCandidates,
  otpSessionProblem,
  rateLimitStep,
  dayKey,
};
