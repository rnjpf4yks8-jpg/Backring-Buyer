// People: role requests, push notifications and account deletion.
//
// Everyone signs up as a buyer. Asking to be a vet, bloodstock agent or staff member sets
// users/{uid}.requestedRole; the administrator gets a push notification and approves or declines in
// the app (People screen). The decision is written as users/{uid}.lastDecision and the person gets a
// push notification too.
//
// Push goes straight to Apple (APNs) with a .p8 key, stored as two secrets:
//   firebase functions:secrets:set APNS_KEY --data-file AuthKey_XXXXXXXXXX.p8
//   firebase functions:secrets:set APNS_KEY_ID        (the 10-character Key ID)
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('node:crypto');
const http2 = require('node:http2');

const APNS_KEY = defineSecret('APNS_KEY');
const APNS_KEY_ID = defineSecret('APNS_KEY_ID');
const TEAM_ID = '8P44VXJJ7X';
const BUNDLE_ID = 'com.example.haintel';

const ROLE_NAMES = { buyer: 'buyer', vet: 'vet', agent: 'bloodstock agent', staff: 'staff member', admin: 'administrator' };
const roleName = role => ROLE_NAMES[role] || role;
const withArticle = role => `${/^[aeiou]/.test(roleName(role)) ? 'an' : 'a'} ${roleName(role)}`;

// ---------- Apple push ----------

let cachedJwt;
/// Apple wants a fresh signed token at most every hour; reuse one for 40 minutes.
function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwt.iat < 40 * 60) return cachedJwt.token;
  const part = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const unsigned = `${part({ alg: 'ES256', kid: APNS_KEY_ID.value().trim() })}.${part({ iss: TEAM_ID, iat: now })}`;
  const signature = crypto.sign('sha256', Buffer.from(unsigned), { key: APNS_KEY.value(), dsaEncoding: 'ieee-p1363' });
  cachedJwt = { iat: now, token: `${unsigned}.${signature.toString('base64url')}` };
  return cachedJwt.token;
}

/// Sends one notification. Resolves with Apple's status and reason; never throws.
function apnsSend(host, deviceToken, payload) {
  return new Promise(resolve => {
    let settled = false;
    const done = result => { if (!settled) { settled = true; client.close(); resolve(result); } };
    const client = http2.connect(`https://${host}`);
    client.on('error', error => done({ status: 0, reason: error.message }));
    let request;
    try {
      request = client.request({
        ':method': 'POST',
        ':path': `/3/device/${deviceToken}`,
        authorization: `bearer ${apnsJwt()}`,
        'apns-topic': BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      });
    } catch (error) {
      return done({ status: 0, reason: error.message });
    }
    let status = 0;
    let body = '';
    request.setEncoding('utf8');
    request.setTimeout(15000, () => done({ status: 0, reason: 'timeout' }));
    request.on('response', headers => { status = headers[':status']; });
    request.on('data', chunk => { body += chunk; });
    request.on('end', () => {
      let reason = '';
      try { reason = JSON.parse(body).reason || ''; } catch { /* empty body on success */ }
      done({ status, reason });
    });
    request.on('error', error => done({ status: 0, reason: error.message }));
    request.end(JSON.stringify(payload));
  });
}

/// Notifies every phone the person is signed in on (users/{uid}/devices/{token}). Dead tokens are removed.
async function pushToPerson(uid, title, body, kind) {
  const db = admin.firestore();
  const devices = await db.collection(`users/${uid}/devices`).get();
  await Promise.all(devices.docs.map(async device => {
    const payload = { aps: { alert: { title, body }, sound: 'default' }, kind };
    // App Store and TestFlight builds use Apple's production server; builds run from Xcode use the sandbox.
    let result = await apnsSend('api.push.apple.com', device.id, payload);
    if (result.status === 400 && result.reason === 'BadDeviceToken') {
      result = await apnsSend('api.sandbox.push.apple.com', device.id, payload);
    }
    if (result.status === 200) return;
    logger.warn(`Push to ${uid} failed: ${result.status} ${result.reason}`);
    if (result.status === 410 || ['BadDeviceToken', 'Unregistered'].includes(result.reason)) await device.ref.delete();
  }));
}

const millis = timestamp => (timestamp && typeof timestamp.toMillis === 'function' ? timestamp.toMillis() : null);

/// Requests go to the administrators; decisions go back to the person who asked.
exports.onPersonChanged = onDocumentWritten(
  { document: 'users/{uid}', secrets: [APNS_KEY, APNS_KEY_ID] },
  async event => {
    const uid = event.params.uid;
    const before = event.data.before.exists ? event.data.before.data() : {};
    const after = event.data.after.exists ? event.data.after.data() : null;
    if (!after) return;
    const jobs = [];

    if (after.requestedRole && after.requestedRole !== before.requestedRole) {
      const who = `${after.name || 'Someone'}${after.email ? ` (${after.email})` : ''}`;
      const admins = await admin.firestore().collection('users').where('role', '==', 'admin').get();
      for (const person of admins.docs) {
        if (person.id === uid) continue;
        jobs.push(pushToPerson(person.id, `New ${roleName(after.requestedRole)} request`,
          `${who} wants to be ${withArticle(after.requestedRole)}. Open Backring Buyer to approve or decline.`, 'request'));
      }
    }

    const decision = after.lastDecision;
    if (decision && millis(decision.at) !== null && millis(decision.at) !== millis(before.lastDecision?.at)) {
      jobs.push(decision.approved
        ? pushToPerson(uid, 'You’re approved', `You can now use Backring Buyer as ${withArticle(decision.role)}.`, 'decision')
        : pushToPerson(uid, 'Request not approved',
          `Your request to be ${withArticle(decision.role)} wasn’t approved. You can keep using Backring Buyer as a buyer.`, 'decision'));
    }

    const results = await Promise.allSettled(jobs);
    for (const result of results) if (result.status === 'rejected') logger.error(`Push failed: ${result.reason}`);
  });

// ---------- Deleting an account ----------

/// Administrator only: deletes a person's sign-in, profile, purchases and devices, and takes them off
/// every sale panel. Opinions they already posted stay. This can't be undone.
exports.deleteAccount = onCall(async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const db = admin.firestore();
  const caller = await db.doc(`users/${request.auth.uid}`).get();
  if (caller.get('role') !== 'admin') throw new HttpsError('permission-denied', 'Only the administrator can delete accounts.');

  const uid = request.data?.uid;
  if (typeof uid !== 'string' || !uid || uid.includes('/')) throw new HttpsError('invalid-argument', 'Whose account?');
  if (uid === request.auth.uid) throw new HttpsError('failed-precondition', 'You can’t delete your own account here.');
  const target = await db.doc(`users/${uid}`).get();
  if (target.get('role') === 'admin') {
    throw new HttpsError('failed-precondition', 'Change this administrator to another role before deleting the account.');
  }

  const sales = await db.collection('sales').get();
  await Promise.all(sales.docs.map(async sale => {
    const panel = sale.get('panel') || {};
    const update = {};
    for (const [slot, member] of Object.entries(panel)) {
      if (member && member.uid === uid) update[`panel.${slot}`] = admin.firestore.FieldValue.delete();
    }
    if (Object.keys(update).length) await sale.ref.update(update);
  }));

  await db.recursiveDelete(db.doc(`users/${uid}`));
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  logger.info(`${request.auth.uid} deleted account ${uid} (${target.get('email') || 'no email'})`);
  return { deleted: true };
});
