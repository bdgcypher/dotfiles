.pragma library

// fzf's FuzzyMatchV2, ported so the launcher filters the way walker does.
//
// Walker's searching is not its own: the elephant providers call into fzf's
// algorithm (github.com/junegunn/fzf/src/algo), specifically
// `FuzzyMatchV2(caseSensitive=false, normalize=true, forward=true, ..., withPos=true)`,
// and the port here is a line-by-line translation of that function plus
// `asciiFuzzyIndex` and the backtrace. The constants, the bonus matrix and the
// two-pass dynamic program are all fzf's, not invented here.
//
// The one addition is `search()`, which mirrors elephant's wrapper in
// pkg/common/fzf.go:
//
//     if res.Start > -1 { res.Score = res.Score - res.Start }
//
// Subtracting the match position is what makes a match early in the field beat
// the same match late in it, and it is part of every score elephant compares
// against MinScore. Without it the numbers do not line up with walker at all.
//
// Two deliberate deviations, both in the "cannot matter here" direction:
//
//   * fzf works on runes and normalises Latin-1 letters; this works on UTF-16
//     code points and does not. App names are ASCII in practice, and the
//     asciiFuzzyIndex fast path below is taken for every ASCII target, which is
//     the path that decides scores for real input.
//   * fzf lowercases the target in place while keeping the original class for
//     bonuses. Same result, but done once per field at build time (see
//     prepare()) instead of per keystroke.
//
// Verified against the real thing: elephant's own `query` command was used as
// the oracle, comparing its score/start/positions for the same targets.

// ── fzf's constants (algo.go) ────────────────────────────────────────────────

var SCORE_MATCH = 16;
var SCORE_GAP_START = -3;
var SCORE_GAP_EXTENSION = -1;

var BONUS_BOUNDARY = SCORE_MATCH / 2;              // 8
var BONUS_NON_WORD = SCORE_MATCH / 2;              // 8
var BONUS_CAMEL123 = BONUS_BOUNDARY + SCORE_GAP_EXTENSION;          // 7
var BONUS_CONSECUTIVE = -(SCORE_GAP_START + SCORE_GAP_EXTENSION);   // 4
var BONUS_FIRST_CHAR_MULTIPLIER = 2;

// `default` scheme, which is what elephant calls Init("default") with.
var BONUS_BOUNDARY_WHITE = BONUS_BOUNDARY + 2;     // 10
var BONUS_BOUNDARY_DELIMITER = BONUS_BOUNDARY + 1; // 9

var DELIMITER_CHARS = "/,:;|";

var CHAR_WHITE = 0;
var CHAR_NON_WORD = 1;
var CHAR_DELIMITER = 2;
var CHAR_LOWER = 3;
var CHAR_UPPER = 4;
var CHAR_LETTER = 5;
var CHAR_NUMBER = 6;

var INITIAL_CHAR_CLASS = CHAR_WHITE;

var WHITE_CHARS = " \t\n\v\f\r\u0085\u00a0";

function charClassOf(code) {
	if (code >= 97 && code <= 122)
		return CHAR_LOWER;
	if (code >= 65 && code <= 90)
		return CHAR_UPPER;
	if (code >= 48 && code <= 57)
		return CHAR_NUMBER;
	if (WHITE_CHARS.indexOf(String.fromCharCode(code)) >= 0)
		return CHAR_WHITE;
	if (DELIMITER_CHARS.indexOf(String.fromCharCode(code)) >= 0)
		return CHAR_DELIMITER;
	if (code > 127)
		// unicode.IsLetter is not available without unicode property escapes,
		// which the QML engine does not guarantee. Anything non-ASCII that is
		// not a delimiter and above the ASCII range is treated as a letter,
		// which is what it is for every desktop file on this system.
		return CHAR_LETTER;
	return CHAR_NON_WORD;
}

function bonusFor(prevClass, cls) {
	if (cls > CHAR_NON_WORD) {
		if (prevClass === CHAR_WHITE)
			return BONUS_BOUNDARY_WHITE;
		if (prevClass === CHAR_DELIMITER)
			return BONUS_BOUNDARY_DELIMITER;
		if (prevClass === CHAR_NON_WORD)
			return BONUS_BOUNDARY;
	}

	if ((prevClass === CHAR_LOWER && cls === CHAR_UPPER)
		|| (prevClass !== CHAR_NUMBER && cls === CHAR_NUMBER))
		return BONUS_CAMEL123;

	if (cls === CHAR_NON_WORD || cls === CHAR_DELIMITER)
		return BONUS_NON_WORD;
	if (cls === CHAR_WHITE)
		return BONUS_BOUNDARY_WHITE;
	return 0;
}

// bonusMatrix[prevClass][class], built once like fzf's global.
var BONUS_MATRIX = (function() {
	var m = [];
	for (var i = 0; i <= CHAR_NUMBER; i++) {
		m.push([]);
		for (var j = 0; j <= CHAR_NUMBER; j++)
			m[i].push(bonusFor(i, j));
	}
	return m;
})();

// ── field preparation ────────────────────────────────────────────────────────
//
// Everything about a target that does not depend on the pattern: its code
// points, the lowercased code points fzf matches against, the character class
// of each (from the *original* case, which is what the camelCase bonus is for)
// and the bonus at each position. Computed once per app list, not per keystroke.

function prepare(text) {
	var s = String(text === undefined || text === null ? "" : text);
	var prepared = {
		chars: [],
		lower: [],
		classes: [],
		bonus: [],
		ascii: true
	};

	var prevClass = INITIAL_CHAR_CLASS;
	for (var i = 0; i < s.length; i++) {
		var code = s.charCodeAt(i);
		var cls = charClassOf(code);
		prepared.chars.push(code);
		prepared.classes.push(cls);
		prepared.lower.push(cls === CHAR_UPPER ? code + 32 : code);
		prepared.bonus.push(BONUS_MATRIX[prevClass][cls]);
		prevClass = cls;
		if (code > 127)
			prepared.ascii = false;
	}

	return prepared;
}

// ── phase 1: the ASCII fast path (asciiFuzzyIndex) ───────────────────────────
//
// Returns the first and last index the match can possibly occupy, or -1 for
// "not a subsequence at all". This is also the cheap rejection: a field that
// fails here never reaches the dynamic program.

function trySkip(chars, caseSensitive, code, from) {
	var start = from;
	if (!caseSensitive && code >= 97 && code <= 122) {
		// Folding the pattern's lowercase letter to its uppercase twin, which
		// fzf does by testing both bytes per character.
		for (var i = start; i < chars.length; i++) {
			if (chars[i] === code || chars[i] === code - 32)
				return i;
		}
		return -1;
	}
	for (var j = start; j < chars.length; j++) {
		if (chars[j] === code)
			return j;
	}
	return -1;
}

// "No match" has to be an object with minIdx < 0, not a bare -1: the caller
// tests idx.minIdx, and on a number that is undefined, so a bare -1 would sail
// past the guard and reach the dynamic program with undefined bounds (NaN
// lengths). Returning the pair keeps the one exit shape.
function noIndex() {
	return { minIdx: -1, maxIdx: -1 };
}

function asciiFuzzyIndex(chars, pattern, caseSensitive) {
	var firstIdx = 0;
	var idx = 0;
	var lastIdx = 0;
	var last = 0;

	for (var pidx = 0; pidx < pattern.length; pidx++) {
		last = pattern[pidx];
		idx = trySkip(chars, caseSensitive, last, idx);
		if (idx < 0)
			return noIndex();
		if (pidx === 0 && idx > 0)
			// Step back to find the right bonus point
			firstIdx = idx - 1;
		lastIdx = idx;
		idx++;
	}

	// Find the last appearance of the pattern's last character, to limit the
	// scan range the way fzf does (`lastIndexByteTwo` looks at the tail).
	if (lastIdx + 1 < chars.length) {
		var fold = !caseSensitive && last >= 97 && last <= 122;
		var end = -1;
		for (var k = chars.length - 1; k > lastIdx; k--) {
			if (chars[k] === last || (fold && chars[k] === last - 32)) {
				end = k;
				break;
			}
		}
		if (end >= 0)
			return { minIdx: firstIdx, maxIdx: end + 1 };
	}
	return { minIdx: firstIdx, maxIdx: lastIdx + 1 };
}

// ── phases 2-4: the dynamic program ──────────────────────────────────────────

function match(field, patternCodes, caseSensitive) {
	var M = patternCodes.length;
	if (M === 0)
		return { start: 0, end: 0, score: 0, positions: [] };

	var chars = field.chars;
	var N = chars.length;
	if (M > N)
		return null;

	// fzf's own guard: a target whose scoring matrix would not fit the caller's
	// scratch slab goes to the greedy V1 instead, and patterns past 1000 runes
	// are refused outright (16-bit scores would overflow). elephant disables the
	// first half by passing a nil slab whenever the product is large, so this
	// threshold is a deliberate deviation -- it only ever fires on a field far
	// larger than anything walker scores in practice (a clipboard entry holding
	// a whole document), where the matrix would be megabytes per keystroke.
	if (M > 1000 || N * M > 102400)
		return greedy(field, patternCodes);

	if (!field.ascii)
		// fzf cannot narrow a non-ASCII target, so it scans the whole thing.
		var idx = { minIdx: 0, maxIdx: N };
	else {
		for (var c = 0; c < M; c++) {
			if (patternCodes[c] > 127)
				return null;
		}
		idx = asciiFuzzyIndex(chars, patternCodes, caseSensitive);
		if (idx.minIdx < 0)
			return null;
	}

	var minIdx = idx.minIdx;
	var maxIdx = idx.maxIdx;
	var lower = field.lower;
	var bonus = field.bonus;

	N = maxIdx - minIdx;

	var H0 = new Array(N);
	var C0 = new Array(N);
	var F = new Array(M);

	var maxScore = 0;
	var maxScorePos = 0;
	var pidx = 0;
	var lastIdx = 0;
	var pchar0 = patternCodes[0];
	var pchar = patternCodes[0];
	var prevH0 = 0;
	var inGap = false;

	for (var off = 0; off < N; off++) {
		var abs = minIdx + off;
		var ch = lower[abs];
		var b = bonus[abs];

		if (ch === pchar) {
			if (pidx < M) {
				F[pidx] = off;
				pidx++;
				pchar = patternCodes[pidx < M ? pidx : M - 1];
			}
			lastIdx = off;
		}

		if (ch === pchar0) {
			var first = SCORE_MATCH + b * BONUS_FIRST_CHAR_MULTIPLIER;
			H0[off] = first;
			C0[off] = 1;
			if (M === 1 && first > maxScore) {
				maxScore = first;
				maxScorePos = off;
				if (b >= BONUS_BOUNDARY)
					break;
			}
			inGap = false;
		} else {
			var gap = prevH0 + (inGap ? SCORE_GAP_EXTENSION : SCORE_GAP_START);
			H0[off] = gap > 0 ? gap : 0;
			C0[off] = 0;
			inGap = true;
		}
		prevH0 = H0[off];
	}

	if (pidx !== M)
		return null;

	if (M === 1)
		return { start: minIdx + maxScorePos, end: minIdx + maxScorePos + 1, score: maxScore, positions: [minIdx + maxScorePos] };

	var f0 = F[0];
	var width = lastIdx - f0 + 1;
	var H = new Array(width * M);
	var C = new Array(width * M);
	for (var i = 0; i < width * M; i++) {
		H[i] = 0;
		C[i] = 0;
	}
	for (var k = 0; k <= lastIdx - f0; k++) {
		H[k] = H0[f0 + k];
		C[k] = C0[f0 + k];
	}

	for (var row0 = 0; row0 < M - 1; row0++) {
		var f = F[row0 + 1];
		var pc = patternCodes[row0 + 1];
		var rowPidx = row0 + 1;
		var row = rowPidx * width;
		var gapState = false;
		var foff = f - f0;
		var cells = lastIdx - f + 1;
		H[row + foff - 1] = 0;

		for (var t = 0; t < cells; t++) {
			// `col` follows fzf: it indexes the trimmed rune array (T), not the
			// original text, which is why every lookup into the prepared field
			// adds minIdx back. Getting this wrong only shows up when the match
			// does not start at position 0 -- "fire" in "Firefox" scores right
			// either way, "cal" in "Tailscale" does not.
			var col = t + f;
			var abs = minIdx + col;
			var here = row + foff + t;
			var left = row + foff + t - 1;
			var diag = row - width + foff + t - 1;
			var diagC = C[diag] !== undefined ? C[diag] : 0;

			var leftScore = H[left] !== undefined ? H[left] : 0;
			var s2 = leftScore + (gapState ? SCORE_GAP_EXTENSION : SCORE_GAP_START);

			var s1 = 0;
			var consecutive = 0;

			if (pc === lower[abs]) {
				var diagScore = H[diag] !== undefined ? H[diag] : 0;
				s1 = diagScore + SCORE_MATCH;
				var bb = bonus[abs];
				consecutive = diagC + 1;
				if (consecutive > 1) {
					var fb = bonus[abs - consecutive + 1];
					if (bb >= BONUS_BOUNDARY && bb > fb) {
						// Break consecutive chunk
						consecutive = 1;
					} else {
						bb = bb > BONUS_CONSECUTIVE ? bb : BONUS_CONSECUTIVE;
						bb = bb > fb ? bb : fb;
					}
				}
				if (s1 + bb < s2) {
					s1 += bonus[abs];
					consecutive = 0;
				} else {
					s1 += bb;
				}
			}

			C[here] = consecutive;
			gapState = s1 < s2;

			var sc = s1 > s2 ? s1 : s2;
			if (sc < 0)
				sc = 0;
			if (rowPidx === M - 1 && sc > maxScore) {
				maxScore = sc;
				maxScorePos = col;
			}
			H[here] = sc;
		}
	}

	// Backtrace for the start offset and the matched positions. fzf only needs
	// the positions for highlighting, but the start is what elephant subtracts
	// from the score, so it has to be found.
	var positions = [];
	var j = maxScorePos;
	var i2 = M - 1;
	var preferMatch = true;

	for (;;) {
		var I = i2 * width;
		var j0 = j - f0;
		var s = H[I + j0];
		var s1 = 0;
		var s2 = 0;

		if (i2 > 0 && j >= F[i2])
			s1 = H[I - width + j0 - 1];
		if (j > F[i2])
			s2 = H[I + j0 - 1];

		if (s > s1 && (s > s2 || (s === s2 && preferMatch))) {
			positions.push(j + minIdx);
			if (i2 === 0)
				break;
			i2--;
		}
		preferMatch = C[I + j0] > 1 || (I + width + j0 + 1 < C.length && C[I + width + j0 + 1] > 0);
		j--;
		if (j < 0)
			break;
	}

	return { start: minIdx + j, end: minIdx + maxScorePos + 1, score: maxScore, positions: positions };
}

// ── the greedy fallback (FuzzyMatchV1) ───────────────────────────────────────
//
// Used only for the oversized targets guarded against above. fzf finds the
// first window that contains the pattern, then walks its end back to the latest
// start that still does, then scores that window -- the same shape as
// FuzzyMatchV1 with forward=true, minus the positions, which the launcher does
// not draw.
function greedy(field, patternCodes) {
	var lower = field.lower;
	var classes = field.classes;
	var M = patternCodes.length;

	var pidx = 0;
	var sidx = -1;
	var eidx = -1;
	var index = 0;

	for (index = 0; index < lower.length; index++) {
		if (lower[index] !== patternCodes[pidx])
			continue;
		if (sidx < 0)
			sidx = index;
		pidx++;
		if (pidx === M) {
			eidx = index + 1;
			break;
		}
	}

	if (sidx < 0 || eidx < 0)
		return null;

	pidx--;
	for (var back = eidx - 1; back >= sidx; back--) {
		if (lower[back] !== patternCodes[pidx])
			continue;
		pidx--;
		if (pidx < 0) {
			sidx = back;
			break;
		}
	}

	// calculateScore, over the window.
	pidx = 0;
	var score = 0;
	var consecutive = 0;
	var firstBonus = 0;
	var inGap = false;
	var prevClass = INITIAL_CHAR_CLASS;
	if (sidx > 0)
		prevClass = classes[sidx - 1];

	for (var idx = sidx; idx < eidx; idx++) {
		var cls = classes[idx];
		if (lower[idx] === patternCodes[pidx]) {
			score += SCORE_MATCH;
			var bonus = BONUS_MATRIX[prevClass][cls];
			if (consecutive === 0)
				firstBonus = bonus;
			else {
				if (bonus >= BONUS_BOUNDARY && bonus > firstBonus)
					firstBonus = bonus;
				bonus = bonus > firstBonus ? bonus : firstBonus;
				bonus = bonus > BONUS_CONSECUTIVE ? bonus : BONUS_CONSECUTIVE;
			}
			score += pidx === 0 ? bonus * BONUS_FIRST_CHAR_MULTIPLIER : bonus;
			inGap = false;
			consecutive++;
			pidx++;
		} else {
			score += inGap ? SCORE_GAP_EXTENSION : SCORE_GAP_START;
			inGap = true;
			consecutive = 0;
			firstBonus = 0;
		}
		prevClass = cls;
	}

	return { start: sidx, end: eidx, score: score, positions: [] };
}

// ── the entry points ─────────────────────────────────────────────────────────

// Somewhere between one and a few hundred items are scored per keystroke, over
// field texts that only change when a provider reloads, so a prepared field is
// worth keeping. The cap is there for the long tail (a clipboard entry can be a
// whole document); anything past it is prepared per call and not remembered.
var CACHE_LIMIT = 4096;
var CACHE_FIELD_LIMIT = 256;
var cache = {};
var cacheSize = 0;

function prepared(text) {
	var key = text === undefined || text === null ? "" : String(text);
	var hit = cache[key];
	if (hit !== undefined)
		return hit;

	var made = prepare(key);
	if (key.length <= CACHE_FIELD_LIMIT) {
		if (cacheSize >= CACHE_LIMIT) {
			cache = {};
			cacheSize = 0;
		}
		cache[key] = made;
		cacheSize++;
	}
	return made;
}

// elephant lowercases and normalizes the query before it reaches fzf
// (algo.NormalizeRunes(strings.ToLower(query)) in its query handler), so the
// pattern is expected lowercase here too.
function codesFor(pattern) {
	var lower = String(pattern === undefined || pattern === null ? "" : pattern).toLowerCase();
	var out = [];
	for (var i = 0; i < lower.length; i++)
		out.push(lower.charCodeAt(i));
	return out;
}

// One field, one pattern: elephant's common.FuzzyScore. The match's start is
// taken off the score here -- and its callers take it off again, which is part
// of the number every MinScore is tuned against, so it is kept.
function score(text, patternCodes) {
	var res = match(prepared(text), patternCodes, false);
	if (res === null)
		return null;
	return { score: res.score - res.start, start: res.start };
}

// elephant's common.FuzzyScore: fzf's score minus where the match starts.
// `field` is prepare()d text. Returns null when there is no match.
function search(field, pattern) {
	if (pattern === "" || pattern.length === 0)
		return { score: 0, start: 0, positions: [] };

	var codes = [];
	for (var i = 0; i < pattern.length; i++)
		codes.push(pattern.charCodeAt(i));

	var res = match(field, codes, false);
	if (res === null)
		return null;

	return { score: res.score - res.start, start: res.start, positions: res.positions };
}
