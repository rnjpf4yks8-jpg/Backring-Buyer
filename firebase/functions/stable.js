// Stable PPs (the second app, StablePPs/): Claude reads an Equibase chart and writes each of your
// horses' past-performance line, and reads a track's condition book into races. The app saves the
// results in stables/{uid}/…; nothing is stored here.
//
// Uses the same ANTHROPIC_API_KEY secret as the conformation suggestion (conformation.js).
// Only the administrator and staff accounts can use it, since every read is billed to that key.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const MODEL = 'claude-sonnet-5-5';
const MAX_PDF_BASE64 = 14 * 1024 * 1024;   // about 10 MB of PDF
const MAX_TEXT = 150000;

const TYPES = ['MSW', 'MCL', 'CLM', 'STR', 'ALW', 'AOC', 'STK', 'HCP', 'OTHER'];
const TRACKS = 'Aqueduct=AQU, Belmont Park=BEL, Saratoga=SAR, Finger Lakes=FL, Laurel Park=LRL, Pimlico=PIM, '
  + 'Timonium=TIM, Charles Town=CT, Mountaineer=MNR, Penn National=PEN, Parx Racing=PRX, Presque Isle Downs=PID, '
  + 'Delaware Park=DEL, Monmouth Park=MTH, Colonial Downs=CNL, Shenandoah Downs=SHD, Keeneland=KEE, '
  + 'Churchill Downs=CD, Ellis Park=ELP, Kentucky Downs=KD, Turfway Park=TP, Thistledown=TDN, Belterra Park=BTP, '
  + 'Mahoning Valley=MVR, Horseshoe Indianapolis=IND, Hawthorne=HAW, FanDuel Sportsbook & Horse Racing=FAN, '
  + 'Canterbury Park=CBY, Prairie Meadows=PRM, Fonner Park=FON, Arapahoe Park=ARP, Remington Park=RP, '
  + 'Will Rogers Downs=WRD, Oaklawn Park=OP, Lone Star Park=LS, Sam Houston=HOU, Retama Park=RET, '
  + 'Gillespie County=GIL, Delta Downs=DED, Evangeline Downs=EVD, Louisiana Downs=LAD, Fair Grounds=FG, '
  + 'Gulfstream Park=GP, Gulfstream Park West=GPW, Tampa Bay Downs=TAM, Turf Paradise=TUP, Arizona Downs=AZD, '
  + 'Zia Park=ZIA, Sunland Park=SUN, Ruidoso Downs=RUI, Albuquerque=ALB, Santa Anita=SA, Del Mar=DMR, '
  + 'Los Alamitos=LA, Pleasanton=PLN, Fresno=FNO, Ferndale=FER, Emerald Downs=EMD, Woodbine=WO, Fort Erie=FE, '
  + 'Hastings=HST, Century Mile=CMR, Assiniboia Downs=ASD';
const STATES = {
  Alabama: 'AL', Arizona: 'AZ', Arkansas: 'AR', California: 'CA', Colorado: 'CO', Florida: 'FL', Georgia: 'GA',
  Illinois: 'IL', Indiana: 'IN', Iowa: 'IA', Kentucky: 'KY', Louisiana: 'LA', Maryland: 'MD', Michigan: 'MI',
  Minnesota: 'MN', Nebraska: 'NE', 'New Jersey': 'NJ', 'New Mexico': 'NM', 'New York': 'NY', Ohio: 'OH',
  Oklahoma: 'OK', Pennsylvania: 'PA', Texas: 'TX', Virginia: 'VA', Washington: 'WA', 'West Virginia': 'WV',
  Ontario: 'ON',
};

// ---------- Claude ----------

const str = { type: ['string', 'null'] };
const num = { type: ['number', 'null'] };
const bool = { type: ['boolean', 'null'] };

const RUN = {
  type: 'object',
  properties: {
    horse: { type: 'string', description: 'The horse’s name exactly as it is in the list you were given.' },
    date: { type: 'string', description: 'YYYY-MM-DD' },
    trackName: str,
    track: { type: 'string', description: `Equibase code from this list: ${TRACKS}; otherwise the code printed in the chart.` },
    race: { type: 'integer' },
    surface: { type: 'string', enum: ['D', 'T', 'A'], description: 'D dirt, T turf (inner turf too), A synthetic or all weather.' },
    distanceF: { type: 'number', description: 'Furlongs: 1 mile = 8, 1 mile 70 yards = 8.318, 1 1/16 miles = 8.5.' },
    about: bool,
    condition: { type: 'string', description: 'As DRF abbreviates it: fst, gd, my, sly, wf, sys on dirt and synthetic; fm, gd, yl, sf, hy on turf.' },
    fractions: { type: 'array', items: { type: 'string' }, description: 'Fractional times as printed, the first three at most, e.g. ["22.45","45.87","58.40"].' },
    final: { type: 'string', description: 'Final time as printed, e.g. "1:11.32".' },
    ages: { type: 'string', description: '"2", "3", "2U", "3U" or "4U" from the conditions (U means and upward).' },
    fillies: { type: 'boolean', description: 'Only fillies, or fillies and mares, could run.' },
    stateBred: { type: ['string', 'null'], description: 'Two-letter state if the race was for state-breds only.' },
    type: { type: 'string', enum: TYPES },
    claimPrice: { type: ['number', 'null'], description: 'This horse’s claiming price (claiming, maiden claiming, or the optional claiming price if it ran for one).' },
    purse: num,
    classText: { type: 'string', description: 'The class the way DRF prints it, short: "Clm 16000N2L", "Md 30000", "MdSpWt 60k", "Alw 50000N1X", "OC 25k/N1X", "Str 20000", "Selima-G3 200k".' },
    stakesName: str,
    grade: { type: ['integer', 'null'] },
    fieldSize: { type: 'integer', description: 'Number of starters.' },
    program: str,
    postPosition: { type: ['integer', 'null'], description: 'The PP column.' },
    start: { type: ['integer', 'null'], description: 'Position at the start.' },
    calls: {
      type: 'array',
      description: 'Every point of call between Start and Fin for this horse, in order.',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string', description: 'e.g. "1/4", "1/2", "Str"' },
          pos: { type: 'integer' },
          lengths: { type: 'string', description: 'Exactly as printed: "Head", "Neck", "Nose", "1/2", "1 1/2", "12". Empty if none.' },
        },
        required: ['label', 'pos'],
      },
    },
    finish: {
      type: 'object',
      properties: {
        pos: { type: 'integer' },
        lengths: { type: 'string', description: 'As printed for this horse at the finish.' },
      },
      required: ['pos'],
    },
    jockey: { type: 'string', description: '"Last, First"' },
    weight: { type: ['integer', 'null'] },
    medEq: { type: 'string', description: 'The M/E column, e.g. "L b".' },
    odds: { type: ['number', 'null'], description: 'Final odds as a number (5-2 is 2.5).' },
    favorite: bool,
    comment: { type: 'string', description: 'The chart comment for this horse.' },
    top3: {
      type: 'array',
      description: 'The first three finishers in order; lengths is how far each finished ahead of the next horse.',
      items: {
        type: 'object',
        properties: { name: { type: 'string' }, weight: { type: ['integer', 'null'] }, lengths: { type: 'string' } },
        required: ['name'],
      },
    },
    earnings: { type: 'number', description: 'Dollars this horse earned in this race, from the Value of Race breakdown by its finishing position; 0 if out of the money.' },
    speed: { type: ['integer', 'null'], description: 'Equibase Speed Figure for this horse in this race, only if the chart prints one.' },
    claimed: { type: ['string', 'null'], description: '"Claimed by … for $…" if this horse was claimed.' },
    trainer: { type: 'string', description: 'This horse’s trainer, from the Trainers list.' },
    owner: { type: 'string', description: 'This horse’s owner, from the Owners list.' },
    conditions: { type: 'string', description: 'The race conditions sentence.' },
    winnerInfo: {
      type: ['object', 'null'],
      description: 'Only if this horse won: the breeding line printed for the winner.',
      properties: {
        color: str, sex: str, sire: str, dam: str, damSire: str,
        foaledIn: { type: ['string', 'null'], description: 'State or country where it was foaled, e.g. "Louisiana".' },
        breeder: str,
      },
    },
  },
  required: ['horse', 'date', 'track', 'race', 'surface', 'distanceF', 'type', 'finish'],
};

const CHART_TOOL = {
  name: 'report_runs',
  description: 'Report each listed horse’s run in this chart as a DRF past-performance line.',
  input_schema: {
    type: 'object',
    properties: {
      runs: { type: 'array', items: RUN },
      notFound: {
        type: 'array',
        description: 'Listed horses that did not start in any race in this chart, with why (not in it, scratched…).',
        items: { type: 'object', properties: { horse: { type: 'string' }, reason: { type: 'string' } }, required: ['horse'] },
      },
    },
    required: ['runs'],
  },
};

const CHART_SYSTEM = `You read Equibase thoroughbred race charts and write a horse's run the way the Daily Racing
Form prints a past-performance line. A chart may cover one race or a whole card.

Charts print beaten lengths small and raised next to each running position. When chart text is pasted
from a web page that small text runs straight into the number before it: "21 1/2" can mean 2nd by 1 1/2,
"1Head" 1st by a head, "103" 10th by 3. Use the field size and the other horses' positions to tell them
apart. In the running-position columns the lengths are how far a horse was ahead of the next horse
(for the leader) or behind the leader.

Report only the horses on the list you are given, by the name on that list (charts print foreign-bred
horses with a country, e.g. "Told (IRE)"). Copy names, times and lengths exactly as printed. Where the
chart doesn't say something, use null. Work out earnings from the "Value of Race" line: each place's
money, by this horse's finishing position.`;

async function askClaude({ system, content, tool, maxTokens }) {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY.value(),
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: maxTokens,
      system,
      tools: [tool],
      tool_choice: { type: 'tool', name: tool.name },
      messages: [{ role: 'user', content }],
    }),
    signal: AbortSignal.timeout(240000),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    logger.error(`Claude API ${response.status}: ${JSON.stringify(body).slice(0, 500)}`);
    throw new HttpsError('unavailable', response.status === 401
      ? 'Claude isn’t set up yet: the ANTHROPIC_API_KEY secret is missing or wrong.'
      : response.status === 429 || response.status === 529
        ? 'Claude is busy right now. Try again in a minute.'
        : 'Claude couldn’t read this right now. Try again in a minute.');
  }
  const input = (body.content || []).find(block => block.type === 'tool_use')?.input;
  if (!input) throw new HttpsError('internal', 'Claude didn’t return anything. Try again.');
  return input;
}

/// The chart or book as a PDF (base64) or text, checked for size.
function documentBlock(data) {
  if (typeof data.pdf === 'string' && data.pdf.length > 100) {
    if (data.pdf.length > MAX_PDF_BASE64) throw new HttpsError('invalid-argument', 'That PDF is too big. Use the chart for one race or one day.');
    return { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: data.pdf } };
  }
  const text = typeof data.text === 'string' ? data.text.trim() : '';
  if (text.length < 100) throw new HttpsError('invalid-argument', 'Nothing to read: paste the whole chart, or pick the PDF.');
  return { type: 'text', text: `Chart text:\n${text.slice(0, MAX_TEXT)}` };
}

async function requireStaff(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const profile = await admin.firestore().doc(`users/${request.auth.uid}`).get();
  if (!['staff', 'admin'].includes(profile.get('role'))) {
    throw new HttpsError('permission-denied',
      'Reading with Claude is switched on for the Backring Buyer administrator and staff. Sign in with that account.');
  }
}

// ---------- Cleaning what Claude returns (the app decodes these types strictly) ----------

const number = v => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v))) ? null : Number(v);
const integer = v => { const n = number(v); return n === null ? null : Math.round(n); };
const text = (v, max = 400) => (v === null || v === undefined) ? '' : String(v).trim().slice(0, max);
const textOrNull = (v, max = 400) => { const t = text(v, max); return t ? t : null; };
const isoDate = v => { const m = String(v || '').match(/^(\d{4})-(\d{2})-(\d{2})/); return m ? `${m[1]}-${m[2]}-${m[3]}` : ''; };
const trackCode = v => String(v || '').toUpperCase().replace(/[^A-Z]/g, '').slice(0, 4);

function lineKey(line) {
  return `${line.date}-${(line.track || 'trk').toUpperCase()}-${line.race || 0}`.replace(/[^A-Za-z0-9_-]/g, '-');
}

function cleanRun(r) {
  const line = {
    date: isoDate(r.date),
    track: trackCode(r.track),
    trackName: text(r.trackName, 80),
    race: integer(r.race),
    surface: ['D', 'T', 'A'].includes(r.surface) ? r.surface : 'D',
    distanceF: number(r.distanceF),
    about: r.about === true,
    condition: text(r.condition, 8).toLowerCase(),
    fractions: Array.isArray(r.fractions) ? r.fractions.map(x => text(x, 12)).filter(Boolean).slice(0, 4) : [],
    final: text(r.final, 12),
    ages: text(r.ages, 4).toUpperCase(),
    fillies: r.fillies === true,
    stateBred: textOrNull(r.stateBred, 2),
    type: TYPES.includes(r.type) ? r.type : 'OTHER',
    claimPrice: number(r.claimPrice),
    purse: number(r.purse),
    classText: text(r.classText, 40),
    stakesName: textOrNull(r.stakesName, 80),
    grade: integer(r.grade),
    fieldSize: integer(r.fieldSize),
    program: text(r.program, 6),
    postPosition: integer(r.postPosition),
    start: integer(r.start),
    calls: Array.isArray(r.calls) ? r.calls.slice(0, 6).map(c => ({ label: text(c?.label, 12), pos: integer(c?.pos), lengths: text(c?.lengths, 12) })) : [],
    finish: { pos: integer(r.finish?.pos), lengths: text(r.finish?.lengths, 12) },
    jockey: text(r.jockey, 60),
    weight: integer(r.weight),
    medEq: text(r.medEq, 12),
    odds: number(r.odds),
    favorite: r.favorite === true,
    comment: text(r.comment, 120),
    top3: Array.isArray(r.top3) ? r.top3.slice(0, 3).map(x => ({ name: text(x?.name, 60), weight: integer(x?.weight), lengths: text(x?.lengths, 12) })) : [],
    earnings: number(r.earnings) ?? 0,
    speed: integer(r.speed),
    claimed: textOrNull(r.claimed, 120),
    trainer: text(r.trainer, 80),
    owner: text(r.owner, 120),
    conditions: text(r.conditions, 600),
    source: 'chart',
    updatedAt: new Date().toISOString(),
  };
  line.id = lineKey(line);
  const w = r.winnerInfo && typeof r.winnerInfo === 'object' ? r.winnerInfo : {};
  const profile = {
    trainer: textOrNull(r.trainer, 80),
    owner: textOrNull(r.owner, 120),
    color: textOrNull(w.color, 30),
    sire: textOrNull(w.sire, 60),
    dam: textOrNull(w.dam, 60),
    damSire: textOrNull(w.damSire, 60),
    breeder: textOrNull(w.breeder, 120),
    stateBred: STATES[text(w.foaledIn, 30)] || null,
  };
  return { line, profile };
}

/// "Told (IRE)" and "TOLD" are the same horse.
const nameKey = name => String(name || '').toLowerCase().replace(/\([a-z]{2,3}\)/g, '').replace(/[^a-z0-9]/g, '');

// ---------- readChart ----------

/**
 * data: { horses: [{id, name}], pdf: base64 } or { horses, text }.
 * Returns { lines: [{horseId, line, profile}], notFound: [{horseId, reason}] }.
 */
exports.readChart = onCall({ secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: '512MiB' }, async request => {
  await requireStaff(request);
  const data = request.data || {};
  const horses = (Array.isArray(data.horses) ? data.horses : [])
    .filter(h => h && typeof h.id === 'string' && typeof h.name === 'string' && h.name.trim())
    .slice(0, 60);
  if (!horses.length) throw new HttpsError('invalid-argument', 'Which horse is this chart for?');

  const doc = documentBlock(data);
  const list = horses.map(h => `- ${h.name.trim()}`).join('\n');
  const input = await askClaude({
    system: CHART_SYSTEM,
    tool: CHART_TOOL,
    maxTokens: 12000,
    content: [doc, { type: 'text', text: `Horses to find:\n${list}\n\nReport each one's run (or put it in notFound).` }],
  });

  const byKey = new Map(horses.map(h => [nameKey(h.name), h]));
  const lines = [];
  const found = new Set();
  for (const run of Array.isArray(input.runs) ? input.runs : []) {
    const horse = byKey.get(nameKey(run?.horse));
    if (!horse || found.has(horse.id)) continue;
    const { line, profile } = cleanRun(run);
    if (!line.date || !line.finish.pos) continue;
    found.add(horse.id);
    lines.push({ horseId: horse.id, line, profile });
  }
  const reasons = new Map((Array.isArray(input.notFound) ? input.notFound : [])
    .map(x => [nameKey(x?.horse), text(x?.reason, 200)]));
  const notFound = horses.filter(h => !found.has(h.id))
    .map(h => ({ horseId: h.id, reason: reasons.get(nameKey(h.name)) || `${h.name} isn’t in this chart.` }));
  logger.info(`readChart: ${lines.length} line(s), ${notFound.length} not found`);
  return { lines, notFound };
});

// ---------- readEquibasePage ----------

const PAGE_RACE = {
  type: 'object',
  properties: {
    date: { type: 'string', description: 'YYYY-MM-DD' },
    track: { type: 'string', description: `Equibase code from this list: ${TRACKS}; otherwise the code printed.` },
    race: { type: ['integer', 'null'] },
    finish: { type: ['integer', 'null'], description: 'Official finishing position.' },
    speed: { type: ['integer', 'null'], description: 'Equibase Speed Figure for this race, if shown.' },
    earnings: { type: ['number', 'null'], description: 'Money this horse earned in the race, if shown.' },
    distanceF: { type: ['number', 'null'], description: 'Furlongs: 1 mile = 8, 1 mile 70 yards = 8.318, 1 1/16 miles = 8.5.' },
    surface: { type: ['string', 'null'], enum: ['D', 'T', 'A', null] },
    type: { type: ['string', 'null'], enum: [...TYPES, null] },
    classText: { type: ['string', 'null'], description: 'Class as printed, shortened DRF style ("Md 30000", "Clm 16000N2L").' },
    fieldSize: { type: ['integer', 'null'] },
  },
  required: ['date', 'track'],
};

const ENTRY = {
  type: ['object', 'null'],
  description: 'The next race (today or later) this horse is entered in, or null if none is shown.',
  properties: {
    date: { type: 'string', description: 'YYYY-MM-DD' },
    trackName: str,
    track: { type: 'string', description: 'Equibase track code.' },
    race: { type: ['integer', 'null'] },
    postTime: { type: ['string', 'null'], description: 'Post time as printed, e.g. "3:45 PM CT".' },
    program: { type: ['string', 'null'], description: 'Program number, e.g. "4" or "1A".' },
    postPosition: { type: ['integer', 'null'] },
    morningLine: { type: ['string', 'null'], description: 'Morning line odds as printed, e.g. "5-2".' },
    jockey: { type: ['string', 'null'], description: '"Last, First"' },
    trainer: str,
    weight: { type: ['integer', 'null'] },
    medEq: { type: ['string', 'null'], description: 'Medication and equipment, e.g. "L b".' },
    distanceF: { type: ['number', 'null'], description: 'Furlongs.' },
    about: bool,
    surface: { type: ['string', 'null'], enum: ['D', 'T', 'A', null] },
    type: { type: ['string', 'null'], enum: [...TYPES, null] },
    classText: { type: ['string', 'null'], description: 'Class shortened DRF style ("Md 30000", "Alw 50000N1X").' },
    purse: num,
    claimPrice: { type: ['number', 'null'], description: 'This horse’s claiming price if entered for one.' },
    fieldSize: { type: ['integer', 'null'], description: 'Horses entered (not counting also-eligibles).' },
    conditions: { type: ['string', 'null'], description: 'The race conditions, under 300 characters.' },
    scratched: bool,
  },
  required: ['date', 'track'],
};

const PAGE_TOOL = {
  name: 'report_horse_page',
  description: 'Report the horse’s upcoming entry and its recent race results from this Equibase text.',
  input_schema: {
    type: 'object',
    properties: {
      entry: ENTRY,
      noEntryReason: { type: ['string', 'null'], description: 'If entry is null, why, in a few words.' },
      races: { type: 'array', items: PAGE_RACE, description: 'Race results listed for this horse, newest first, at most 30.' },
    },
    required: ['races'],
  },
};

function cleanEntry(r) {
  if (!r || typeof r !== 'object') return null;
  const date = isoDate(r.date);
  if (!date) return null;
  return {
    date,
    track: trackCode(r.track) || null,
    trackName: textOrNull(r.trackName, 80),
    race: integer(r.race),
    postTime: textOrNull(r.postTime, 20),
    program: textOrNull(r.program, 6),
    postPosition: integer(r.postPosition),
    morningLine: textOrNull(r.morningLine, 10),
    jockey: textOrNull(r.jockey, 60),
    trainer: textOrNull(r.trainer, 80),
    weight: integer(r.weight),
    medEq: textOrNull(r.medEq, 12),
    distanceF: number(r.distanceF),
    about: r.about === true,
    surface: ['D', 'T', 'A'].includes(r.surface) ? r.surface : null,
    type: TYPES.includes(r.type) ? r.type : null,
    classText: textOrNull(r.classText, 40),
    purse: number(r.purse),
    claimPrice: number(r.claimPrice),
    fieldSize: integer(r.fieldSize),
    conditions: textOrNull(r.conditions, 400),
    scratched: r.scratched === true,
    source: 'pasted',
    updatedAt: new Date().toISOString(),
  };
}

function cleanPageRace(r) {
  const date = isoDate(r?.date);
  const track = trackCode(r?.track);
  if (!date || !track) return null;
  return {
    date, track,
    race: integer(r.race),
    finish: integer(r.finish),
    speed: integer(r.speed),
    earnings: number(r.earnings),
    distanceF: number(r.distanceF),
    surface: ['D', 'T', 'A'].includes(r.surface) ? r.surface : null,
    type: TYPES.includes(r.type) ? r.type : null,
    classText: textOrNull(r.classText, 40),
    fieldSize: integer(r.fieldSize),
  };
}

/**
 * data: { horse: {id, name}, text } — the horse's Equibase page (or a card's entries) copied from Safari.
 * Returns { entry, noEntryReason, races }: the next race it's entered in, and its results with
 * Equibase Speed Figures, for the app to add to the horse.
 */
exports.readEquibasePage = onCall({ secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 180, memory: '256MiB' }, async request => {
  await requireStaff(request);
  const data = request.data || {};
  const name = text(data.horse?.name, 80);
  if (!name) throw new HttpsError('invalid-argument', 'Which horse is this page for?');
  const doc = documentBlock({ text: data.text });
  const today = new Date().toISOString().slice(0, 10);
  const r = await askClaude({
    system: `You read text copied from Equibase pages about thoroughbreds: a horse's profile (results, entries,
workouts) or a race card's entries. Today is ${today}. Report the next race the named horse is entered in
(today or later; not workouts), and the race results listed for that horse with finishing position, Equibase
Speed Figure and earnings where shown. Copy values exactly as printed; use null where the text doesn't say.`,
    tool: PAGE_TOOL,
    maxTokens: 6000,
    content: [doc, { type: 'text', text: `Horse: ${name}` }],
  });
  const entry = cleanEntry(r.entry);
  const races = (Array.isArray(r.races) ? r.races : []).map(cleanPageRace).filter(Boolean).slice(0, 30);
  logger.info(`readEquibasePage: ${name} entry ${entry ? `${entry.date} ${entry.track}` : 'none'}, ${races.length} races`);
  return {
    entry: entry && entry.date >= today ? entry : null,
    noEntryReason: entry && entry.date < today ? 'The only entry shown has already run.' : textOrNull(r.noEntryReason, 200),
    races,
  };
});

// ---------- readConditionBook ----------

const BOOK_RACE = {
  type: 'object',
  properties: {
    date: { type: 'string', description: 'YYYY-MM-DD' },
    raceNo: { type: ['string', 'null'], description: 'Book race number as printed.' },
    type: { type: 'string', enum: TYPES },
    name: { type: ['string', 'null'], description: 'Stakes name.' },
    purse: num,
    claim: { type: ['number', 'null'], description: 'Claiming price (the highest if a range; the optional claiming price for AOC).' },
    claimLow: { type: ['number', 'null'], description: 'Lowest claiming price if a range.' },
    ages: { type: 'string', description: '"2", "3", "2U", "3U" or "4U" (U means and upward).' },
    sex: { type: 'string', enum: ['F', 'O'], description: 'F if only fillies, or fillies and mares, may run; else O.' },
    stateBred: { type: ['string', 'null'], description: 'Two-letter state if only state-breds may run.' },
    maiden: { type: 'boolean' },
    nw: {
      type: ['object', 'null'],
      description: 'lifetime n=2 for "which have never won two races"; otherThan n=1 for "never won a race other than maiden, claiming, starter or optional claiming"; since n=1 with a date for "which have not won a race since …".',
      properties: { kind: { type: 'string', enum: ['lifetime', 'otherThan', 'since'] }, n: { type: 'integer' }, since: str },
      required: ['kind', 'n'],
    },
    starter: {
      type: ['object', 'null'],
      description: 'Starter allowance: "which have started for a claiming price of $10,000 or less (since …)".',
      properties: { claim: { type: 'number' }, since: str },
      required: ['claim'],
    },
    distanceF: { type: 'number', description: 'Furlongs: 1 mile = 8, 1 mile 70 yards = 8.318, 1 1/16 = 8.5.' },
    distanceText: { type: 'string', description: 'Distance as printed.' },
    surface: { type: 'string', enum: ['D', 'T', 'A'] },
    sub: { type: 'boolean', description: 'Printed as a substitute race.' },
    text: { type: 'string', description: 'The conditions in under 160 characters.' },
  },
  required: ['date', 'type', 'ages', 'sex', 'distanceF', 'surface'],
};

const BOOK_TOOL = {
  name: 'report_races',
  description: 'Report every race printed on these condition-book pages.',
  input_schema: { type: 'object', properties: { races: { type: 'array', items: BOOK_RACE } }, required: ['races'] },
};

function cleanBookRace(r) {
  const date = isoDate(r?.date);
  if (!date || !TYPES.includes(r?.type)) return null;
  const nwKind = ['lifetime', 'otherThan', 'since'].includes(r.nw?.kind) ? r.nw.kind : null;
  const nwN = integer(r.nw?.n);
  const starterClaim = number(r.starter?.claim);
  return {
    date,
    raceNo: textOrNull(r.raceNo, 6),
    type: r.type,
    name: textOrNull(r.name, 80),
    purse: number(r.purse),
    claim: number(r.claim) || null,
    claimLow: number(r.claimLow) || null,
    ages: text(r.ages, 4).toUpperCase(),
    sex: r.sex === 'F' ? 'F' : 'O',
    stateBred: textOrNull(r.stateBred, 2),
    maiden: r.maiden === true,
    nw: nwKind && nwN ? { kind: nwKind, n: nwN, since: isoDate(r.nw.since) || null } : null,
    starter: starterClaim ? { claim: starterClaim, since: isoDate(r.starter.since) || null } : null,
    distanceF: number(r.distanceF),
    distanceText: text(r.distanceText, 30),
    surface: ['D', 'T', 'A'].includes(r.surface) ? r.surface : 'D',
    sub: r.sub === true,
    text: text(r.text, 200),
  };
}

/**
 * data: { trackName, year, first, last, pdf: base64 of those pages } (or text).
 * Returns { races: [...] } for those pages; the app joins the parts and saves the book.
 */
exports.readConditionBook = onCall({ secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: '512MiB' }, async request => {
  await requireStaff(request);
  const data = request.data || {};
  const trackName = text(data.trackName, 80) || 'the track';
  const year = integer(data.year) || new Date().getFullYear();
  const first = integer(data.first) || 1;
  const last = integer(data.last) || first;
  const doc = documentBlock(data);
  const input = await askClaude({
    system: `You read thoroughbred condition books and list the races in them. Day headings (like
"SATURDAY, NOVEMBER 14") give the date of the races under them; a race may continue from the previous page.
Skip pages that are only rules, stakes nominations, lists or ads.`,
    tool: BOOK_TOOL,
    maxTokens: 16000,
    content: [doc, { type: 'text', text: `These are pages ${first}–${last} of the ${trackName} condition book (${year}). List every race on them.` }],
  });
  const races = (Array.isArray(input.races) ? input.races : []).map(cleanBookRace).filter(Boolean).slice(0, 200);
  logger.info(`readConditionBook ${trackName} pages ${first}-${last}: ${races.length} races`);
  return { races };
});
