// Checks every opinion purchase with Apple. The app saves users/{uid}/purchases/{saleId_hip_slot}
// with the App Store's signed transaction; if it isn't a real purchase of the right product, used
// only once, the record is deleted and the opinion locks again.
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');

admin.initializeApp();
const db = admin.firestore();

// Staff-only AI conformation suggestion from the sale walk video (see conformation.js).
exports.suggestConformation = require('./conformation').suggestConformation;
// Signing up or upgrading to staff with the staff code (see staff.js).
exports.claimStaff = require('./staff').claimStaff;

const BUNDLE_ID = 'com.example.haintel';
const APP_APPLE_ID = 6826705029;
const PRODUCTS = { vet: 'com.example.haintel.vetopinion', agent: 'com.example.haintel.agentopinion' };
const ROOT_CERTS = [
  'https://www.apple.com/certificateauthority/AppleRootCA-G3.cer',
  'https://www.apple.com/certificateauthority/AppleRootCA-G2.cer',
  'https://www.apple.com/appleca/AppleIncRootCertificate.cer',
];

let verifiers;
async function getVerifiers() {
  if (!verifiers) {
    const certs = await Promise.all(ROOT_CERTS.map(async url => Buffer.from(await (await fetch(url)).arrayBuffer())));
    // App Store purchases are Production; TestFlight purchases are Sandbox.
    verifiers = [
      new SignedDataVerifier(certs, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID),
      new SignedDataVerifier(certs, true, Environment.SANDBOX, BUNDLE_ID),
    ];
  }
  return verifiers;
}

async function decode(signed) {
  let lastError;
  for (const verifier of await getVerifiers()) {
    try {
      return await verifier.verifyAndDecodeTransaction(signed);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

exports.verifyPurchase = onDocumentCreated('users/{uid}/purchases/{purchaseId}', async event => {
  const { uid, purchaseId } = event.params;
  const data = event.data.data();
  const reject = async reason => {
    logger.warn(`Removed purchase ${uid}/${purchaseId}: ${reason}`);
    await event.data.ref.delete();
  };

  if (!data.signedTransaction) {
    // Test purchases (no App Store receipt) are allowed only while config/app.testPurchases is on.
    const config = await db.doc('config/app').get();
    if (config.get('testPurchases') === true) return;
    return reject('no App Store transaction');
  }

  let transaction;
  try {
    transaction = await decode(data.signedTransaction);
  } catch (error) {
    return reject(`signature check failed: ${error.message}`);
  }

  const slot = purchaseId.split('_').pop();
  const expected = slot.startsWith('vet') ? PRODUCTS.vet : PRODUCTS.agent;
  if (transaction.productId !== expected) return reject(`product ${transaction.productId}, expected ${expected}`);
  if (String(transaction.transactionId) !== String(data.transactionId)) return reject('transaction id mismatch');
  if (transaction.revocationDate) return reject('refunded or revoked');

  // Each App Store transaction unlocks one opinion, once.
  const claim = db.doc(`appStoreTransactions/${transaction.transactionId}`);
  const claimed = await db.runTransaction(async tx => {
    const existing = await tx.get(claim);
    if (existing.exists) {
      const owner = existing.data();
      return owner.uid === uid && owner.purchaseId === purchaseId;
    }
    tx.create(claim, {
      uid, purchaseId,
      productId: transaction.productId,
      environment: transaction.environment,
      purchaseDate: transaction.purchaseDate,
      price: transaction.price ?? null,
      currency: transaction.currency ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed) return reject(`transaction ${transaction.transactionId} already used`);
  await event.data.ref.set({ verified: true, environment: transaction.environment }, { merge: true });
});
