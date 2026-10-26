// AI conformation suggestion from the sale walk video. Staff tap "Suggest from walk video" in the app;
// this pulls still frames from across the video, asks Claude for a C grade with reasons, and returns it.
// Nothing is saved here: the grade goes live only when staff accept it and tap Save in the app.
//
// Needs the ANTHROPIC_API_KEY secret: firebase functions:secrets:set ANTHROPIC_API_KEY
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const { execFile } = require('node:child_process');
const ffmpegPath = require('ffmpeg-static');
const admin = require('firebase-admin');

const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const MODEL = 'claude-opus-5-5';
const FRAME_COUNT = 12;
const MIN_FRAMES = 4;

const SYSTEM = `You are an experienced Thoroughbred bloodstock conformation judge grading sale horses
(mostly yearlings) for buyers. You are given still frames taken in order from one horse's sale walk video.

Grade conformation on a 1-10 scale in half points:
- 9-10: exceptional, near-faultless, top few percent of a select sale
- 7.5-8.5: very good, minor faults only
- 6-7: average sale horse, some faults that are unlikely to limit it
- 4.5-5.5: below average, faults a vet or buyer would question
- 1-4: significant faults likely to affect soundness or racing ability
Most horses at a sale fall between 5 and 7.5. Do not inflate grades.

Judge what the frames show: overall balance and proportion; neck, shoulder angle and withers; back,
loin and hip; depth of girth; straightness and set of the forelegs (knees, cannons, pasterns, feet) and
hind legs (hocks, angles); muscling and substance for the horse's age; and from frames walking toward or
away from the camera, whether the horse tracks straight or paddles, wings or toes in or out.

Only describe what you can actually see. Video frames can be blurry, partly blocked by the handler, or
taken from poor angles; lower your confidence when they are, and say what you could not judge. If no
frame shows the horse clearly, give your best grade with low confidence and explain why.`;

const TOOL = {
  name: 'conformation_grade',
  description: 'Report the conformation grade for this horse.',
  input_schema: {
    type: 'object',
    properties: {
      grade: { type: 'number', description: 'Conformation grade, 1 to 10 in half points.' },
      confidence: { type: 'string', enum: ['low', 'medium', 'high'],
                    description: 'How well the frames let you judge this horse.' },
      summary: { type: 'string', description: 'One plain line, under 110 characters, on why it got this grade.' },
      strengths: { type: 'array', items: { type: 'string' }, description: 'Short phrases, at most 4.' },
      faults: { type: 'array', items: { type: 'string' }, description: 'Short phrases, at most 4. Empty if none seen.' },
      limits: { type: 'string', description: 'What the video did not let you judge, in one line. Empty if nothing.' },
    },
    required: ['grade', 'confidence', 'summary', 'strengths', 'faults', 'limits'],
  },
};

/// Runs ffmpeg and resolves with its output, even when it exits with an error.
function ffmpeg(args, timeout = 60000) {
  return new Promise(resolve => {
    execFile(ffmpegPath, args, { encoding: 'buffer', maxBuffer: 20 * 1024 * 1024, timeout },
      (error, stdout, stderr) => resolve({ error, stdout, stderr: stderr.toString() }));
  });
}

/// Length of the video in seconds. ffmpeg reads only the start (and index) over HTTP, not the whole file.
async function videoSeconds(url) {
  const { stderr } = await ffmpeg(['-hide_banner', '-i', url]);
  const match = stderr.match(/Duration: (\d+):(\d+):(\d+(?:\.\d+)?)/);
  if (!match) {
    logger.warn(`Couldn't read video length: ${stderr.slice(-500)}`);
    throw new HttpsError('failed-precondition',
      'Couldn’t open the walk video. Re-upload it on the Sale Walk Video button, then try again.');
  }
  return Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]);
}

/// One JPEG frame at `seconds`, at most 1280 px on its long side, or null if that spot can't be read.
async function frameAt(url, seconds) {
  const { error, stdout } = await ffmpeg([
    '-hide_banner', '-loglevel', 'error', '-ss', seconds.toFixed(2), '-i', url,
    '-frames:v', '1', '-vf', 'scale=1280:1280:force_original_aspect_ratio=decrease',
    '-q:v', '4', '-f', 'image2pipe', '-vcodec', 'mjpeg', 'pipe:1',
  ]);
  return error || !stdout.length ? null : stdout;
}

/// Frames spread evenly across the video, skipping the first and last few percent.
async function extractFrames(url) {
  const duration = await videoSeconds(url);
  const times = Array.from({ length: FRAME_COUNT }, (_, i) =>
    duration * (0.04 + 0.92 * (FRAME_COUNT === 1 ? 0.5 : i / (FRAME_COUNT - 1))));
  const frames = [];
  for (let i = 0; i < times.length; i += 4) {
    const batch = await Promise.all(times.slice(i, i + 4).map(async t => ({ t, jpeg: await frameAt(url, t) })));
    frames.push(...batch.filter(f => f.jpeg));
  }
  return frames;
}

function clock(seconds) {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

async function askClaude(frames, hip) {
  const about = [hip.foaled && `foaled ${hip.foaled}`, hip.color, hip.sex].filter(Boolean).join(' ');
  const content = [];
  frames.forEach((frame, i) => {
    content.push({ type: 'text', text: `Frame ${i + 1} of ${frames.length} (at ${clock(frame.t)}):` });
    content.push({ type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: frame.jpeg.toString('base64') } });
  });
  content.push({ type: 'text', text: `These are frames from the sale walk video of Hip ${hip.number}`
    + `${about ? ` (${about})` : ''}. Grade this horse's conformation.` });

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': ANTHROPIC_API_KEY.value(),
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1500,
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: TOOL.name },
      messages: [{ role: 'user', content }],
    }),
    signal: AbortSignal.timeout(180000),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    logger.error(`Claude API ${response.status}: ${JSON.stringify(body).slice(0, 500)}`);
    throw new HttpsError('unavailable', response.status === 401
      ? 'AI grading isn’t set up yet: the ANTHROPIC_API_KEY secret is missing or wrong.'
      : 'The AI couldn’t grade this video right now. Try again in a minute.');
  }
  const result = (body.content || []).find(block => block.type === 'tool_use')?.input;
  if (!result || typeof result.grade !== 'number') {
    throw new HttpsError('internal', 'The AI didn’t return a grade. Try again.');
  }
  return result;
}

const shortList = list => (Array.isArray(list) ? list : []).map(String).map(s => s.trim()).filter(Boolean).slice(0, 4);

exports.suggestConformation = onCall(
  { secrets: [ANTHROPIC_API_KEY], timeoutSeconds: 300, memory: '1GiB' },
  async request => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in as staff first.');
    const db = admin.firestore();
    const profile = await db.doc(`users/${request.auth.uid}`).get();
    if (!['staff', 'admin'].includes(profile.get('role'))) throw new HttpsError('permission-denied', 'Only staff can grade hips.');

    const { saleId, hip: hipNumber } = request.data || {};
    if (typeof saleId !== 'string' || !/^[\w-]+$/.test(saleId) || !Number.isInteger(hipNumber) || hipNumber < 1) {
      throw new HttpsError('invalid-argument', 'Which sale and hip?');
    }
    const snap = await db.doc(`sales/${saleId}/hips/${hipNumber}`).get();
    if (!snap.exists) throw new HttpsError('not-found', `Hip ${hipNumber} isn’t saved in this sale yet.`);
    const hip = snap.data();

    const url = typeof hip.walkVideoURL === 'string' ? hip.walkVideoURL.trim() : '';
    if (!/^https:\/\//i.test(url)) {
      throw new HttpsError('failed-precondition',
        'This hip has no walk video yet. Add one on the Sale Walk Video button, save, then try again.');
    }
    if (/(^|\.)(vimeo\.com|youtube\.com|youtu\.be)\//i.test(url.replace(/^https:\/\//i, ''))) {
      throw new HttpsError('failed-precondition',
        'This walk video is a Vimeo or YouTube link, which the AI can’t open. Upload the video file on the Sale Walk Video button instead.');
    }

    const frames = await extractFrames(url);
    if (frames.length < MIN_FRAMES) {
      throw new HttpsError('failed-precondition',
        'Couldn’t read enough of the walk video. Re-upload it on the Sale Walk Video button, then try again.');
    }

    const result = await askClaude(frames, hip);
    const grade = Math.min(10, Math.max(1, Math.round(result.grade * 2) / 2));
    logger.info(`Suggested C ${grade} for ${saleId} hip ${hipNumber} from ${frames.length} frames`);
    return {
      grade,
      confidence: ['low', 'medium', 'high'].includes(result.confidence) ? result.confidence : 'low',
      summary: String(result.summary || '').trim().slice(0, 160),
      strengths: shortList(result.strengths),
      faults: shortList(result.faults),
      limits: String(result.limits || '').trim(),
      frames: frames.length,
    };
  });
