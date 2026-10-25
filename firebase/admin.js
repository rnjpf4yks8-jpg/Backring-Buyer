// HAINTEL admin tasks for staff. Needs a Firebase service account key:
//   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
//
//   node admin.js create-sale <saleId> "<name>" "<company>" "<date>"
//   node admin.js import-hips <saleId> <file.csv>
//   node admin.js set-role <email> <buyer|staff|vet|agent> "<name>"
//   node admin.js assign <saleId> <vet1|vet2|bs1|bs2> <email> "<practice or agency>"
//   node admin.js test-purchases <on|off>
const fs = require('fs');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

const SLOTS = ['vet1', 'vet2', 'bs1', 'bs2'];
const ROLES = ['buyer', 'staff', 'vet', 'agent'];

async function createSale(saleId, name, company, date) {
  if (!saleId || !name || !company || !date) throw usage();
  const ref = db.collection('sales').doc(saleId);
  const existing = await ref.get();
  await ref.set({
    id: saleId, name, company, date,
    panel: existing.exists ? existing.data().panel || {} : {},
    vetPrice: 25, agentPrice: 50,
  }, { merge: true });
  await db.collection('config').doc('app').set({ currentSale: saleId }, { merge: true });
  console.log(`Sale ${saleId} saved. It shows in the app's sales list, marked NOW as the featured sale.`);
}

async function importHips(saleId, file) {
  if (!saleId || !file) throw usage();
  const rows = parseCSV(fs.readFileSync(file, 'utf8'));
  const header = rows.shift().map(h => h.trim());
  const col = name => header.indexOf(name);
  for (const required of ['number', 'sire', 'dam']) {
    if (col(required) < 0) throw new Error(`The CSV needs a "${required}" column. See hips-template.csv.`);
  }
  const hipsRef = db.collection('sales').doc(saleId).collection('hips');
  let added = 0, updated = 0;
  for (const row of rows) {
    if (row.every(cell => cell.trim() === '')) continue;
    const get = name => (col(name) >= 0 ? (row[col(name)] || '').trim() : '');
    const number = parseInt(get('number'), 10);
    if (!number) { console.warn(`Skipped a row with no hip number: ${row.join(',')}`); continue; }

    // Catalog fields only. Staff edits made in the app (vet report, HP, media, history) are kept.
    const catalog = {
      number,
      name: get('name'),
      sex: get('sex') || 'colt',
      color: get('color'),
      foaled: get('foaled'),
      session: get('session'),
      barn: get('barn'),
      consignor: get('consignor'),
      pedigree: {
        sire: get('sire'), sireSire: get('sireSire'), sireDam: get('sireDam'),
        dam: get('dam'), damSire: get('damSire'), damDam: get('damDam'),
      },
    };
    const reserve = parseInt(get('reserve').replace(/[$,]/g, ''), 10);
    if (reserve) catalog.reserve = reserve;
    // Optional links (catalog page, walk video, sale picture) and breeding-stock details (sold as, covering sire).
    for (const key of ['pedigreeURL', 'walkVideoURL', 'photoURL', 'walkVideoLength', 'soldAs', 'coveringSire']) {
      if (get(key)) catalog[key] = get(key);
    }

    const ref = hipsRef.doc(String(number));
    const snap = await ref.get();
    if (snap.exists) {
      await ref.set(catalog, { merge: true });
      updated++;
    } else {
      // Every field the app expects, so new hips open cleanly.
      await ref.set({
        ...catalog,
        vetReport: { radiographs: 'clean', radiographNotes: '', scope: 'clean', scopeNotes: '', filed: '' },
        auctionHistory: [],
        walkVideoLength: '',
        opinionsIn: [],
      });
      added++;
    }
  }
  console.log(`Imported into ${saleId}: ${added} new hips, ${updated} updated.`);
}

async function setRole(email, role, name) {
  if (!email || !ROLES.includes(role)) throw usage();
  const user = await admin.auth().getUserByEmail(email);
  const ref = db.collection('users').doc(user.uid);
  const snap = await ref.get();
  await ref.set({
    uid: user.uid,
    name: name || (snap.exists ? snap.data().name : '') || user.displayName || email,
    role,
  }, { merge: true });
  console.log(`${email} is now ${role}.`);
  return user;
}

async function assign(saleId, slot, email, org) {
  if (!saleId || !SLOTS.includes(slot) || !email) throw usage();
  const role = slot.startsWith('vet') ? 'vet' : 'agent';
  const user = await setRole(email, role);
  const profile = (await db.collection('users').doc(user.uid).get()).data();
  await db.collection('sales').doc(saleId).set({
    panel: { [slot]: { uid: user.uid, name: profile.name, org: org || '' } },
  }, { merge: true });
  console.log(`${profile.name} posts ${slot} for ${saleId}.`);
}

async function testPurchases(state) {
  if (!['on', 'off'].includes(state)) throw usage();
  await db.collection('config').doc('app').set({ testPurchases: state === 'on' }, { merge: true });
  console.log(`Test purchases ${state}.`);
}

// Minimal CSV parser: commas, quoted fields, doubled quotes, CRLF.
function parseCSV(text) {
  const rows = [];
  let row = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); rows.push(row); row = []; cell = '';
    } else cell += c;
  }
  if (cell !== '' || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

function usage() {
  return new Error(fs.readFileSync(__filename, 'utf8').split('\n').slice(0, 9).join('\n'));
}

const [command, ...args] = process.argv.slice(2);
const commands = {
  'create-sale': createSale,
  'import-hips': importHips,
  'set-role': setRole,
  'assign': assign,
  'test-purchases': testPurchases,
};

Promise.resolve()
  .then(() => (commands[command] || (() => { throw usage(); }))(...args))
  .then(() => process.exit(0))
  .catch(err => { console.error(err.message); process.exit(1); });
