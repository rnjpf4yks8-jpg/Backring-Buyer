// Makes the signed-in user the Administrator when they enter the right code and Backring Buyer has no
// administrator yet. After that everyone else asks for staff (or vet, or agent) at sign-up or on the
// Account screen, and the administrator approves them. The administrator can also make others staff
// or administrator on the People screen.
//
// The code is a Firebase secret, so it never ships in the app:
//   firebase functions:secrets:set STAFF_CODE
// After 10 wrong tries an account is locked out of this.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('node:crypto');

const STAFF_CODE = defineSecret('STAFF_CODE');
const MAX_WRONG_TRIES = 10;

/// Compares without leaking how much of the code matched.
function sameCode(a, b) {
  const hash = text => crypto.createHash('sha256').update(text).digest();
  return crypto.timingSafeEqual(hash(a), hash(b));
}

exports.claimStaff = onCall({ secrets: [STAFF_CODE] }, async request => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const uid = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.doc(`users/${uid}`);
  const triesRef = db.doc(`staffCodeAttempts/${uid}`);

  const secret = STAFF_CODE.value().trim();
  if (secret.length < 6) {
    throw new HttpsError('failed-precondition', 'The administrator code isn’t set up yet (STAFF_CODE secret, see firebase/README.md).');
  }
  const tries = (await triesRef.get()).get('count') || 0;
  if (tries >= MAX_WRONG_TRIES) {
    throw new HttpsError('resource-exhausted', 'Too many wrong codes. Ask the administrator for a role instead.');
  }

  const code = String(request.data?.code ?? '').trim();
  if (!code || !sameCode(code, secret)) {
    await triesRef.set({ count: tries + 1, lastTry: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    logger.warn(`Wrong administrator code from ${uid} (${tries + 1} of ${MAX_WRONG_TRIES})`);
    throw new HttpsError('permission-denied', 'That code isn’t right.');
  }

  const user = await userRef.get();
  if (!user.exists) throw new HttpsError('failed-precondition', 'Finish creating your account first, then enter the code.');
  if (user.get('role') === 'admin') return { role: 'admin' };

  const admins = await db.collection('users').where('role', '==', 'admin').limit(1).get();
  if (!admins.empty) {
    throw new HttpsError('failed-precondition',
      'Backring Buyer already has an administrator. Ask for a role on this screen and they’ll approve you.');
  }

  await userRef.update({
    role: 'admin',
    requestedRole: admin.firestore.FieldValue.delete(),
    requestedAt: admin.firestore.FieldValue.delete(),
  });
  await triesRef.delete();
  logger.info(`${uid} (${user.get('email') || 'no email'}) is now the administrator`);
  return { role: 'admin' };
});
