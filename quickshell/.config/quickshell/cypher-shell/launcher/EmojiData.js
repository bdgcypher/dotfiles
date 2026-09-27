.pragma library

// Logic for the emoji picker, kept out of the QML so the grid file stays layout.
//
// The data comes from data/emoji/emojis.json (see scripts/build-emoji-data.py),
// where each entry is:
//
//   { c: char, l: label, h: hexcode, g: group index, o: CLDR order,
//     s: [shortcodes], t: [tags], k: [char per tone] | null }
//
// Everything here is a pure function so the picker's behaviour -- what matches a
// search, which section an emoji lands in, what a tone does to it -- can be
// driven and checked from the shell's IPC rather than by looking at the screen.

// Tabs: one per category, with All in front. Icons are emoji rather than Nerd
// Font glyphs because the font stack renders emoji reliably (Noto Color Emoji is
// installed) while an icon codepoint that is missing draws an empty box.
//
// The picks are the drawn-in-colour ones on purpose. Monochrome emoji (the
// soccer ball, the chequered flag, the bust, the airplane, the magnifier) have
// no hue at all, and at an inactive tab's opacity they measured as barely-there
// grey smudges in a screenshot. Every tab is a coloured glyph.
var ALL_KEY = "__all__";

function tabIcon(key) {
	var icons = {
		// A clock, not the magnifier: this tab is the recently used emoji, so
		// history reads better than search -- and the magnifier was the last
		// monochrome glyph on the strip.
		"__all__": "\uD83D\uDD53",           // clock face four o'clock (Recents)
		"smileys-emotion": "\uD83D\uDE00",   // grinning face
		"people-body": "\uD83D\uDC4D",       // thumbs up
		"animals-nature": "\uD83D\uDC36",    // dog face
		"food-drink": "\uD83C\uDF54",        // hamburger
		"travel-places": "\uD83C\uDF0D",     // globe (the airplane is monochrome)
		"activities": "\uD83C\uDFC0",        // basketball
		"objects": "\uD83D\uDCA1",           // light bulb
		"symbols": "\u2764\uFE0F",           // red heart
		"flags": "\uD83D\uDEA9"              // triangular flag
	}
	return icons[key] || "\u2022"
}

// The five tone modifiers, in the order the dataset's `k` array is indexed by.
var TONE_MODIFIERS = [
	"\uD83C\uDFFB", // light
	"\uD83C\uDFFC", // medium-light
	"\uD83C\uDFFD", // medium
	"\uD83C\uDFFE", // medium-dark
	"\uD83C\uDFFF"  // dark
]

// ── query handling ───────────────────────────────────────────────────────────
//
// A query is matched with or without its colons and with underscores or spaces,
// so ":grinning_face", "grinning face" and "grinning" all find the same emoji.

function normalize(query) {
	var q = String(query === undefined || query === null ? "" : query).trim().toLowerCase()
	if (q.charAt(0) === ":")
		q = q.slice(1)
	if (q.charAt(q.length - 1) === ":")
		q = q.slice(0, -1)
	return q.split("_").join(" ").split("-").join(" ")
}

// Higher is a better match; -1 means no match at all.
//
// The order is deliberate: a shortcode is how people name an emoji they cannot
// spell ("+1"), so an exact shortcode beats everything, and a label beats a tag.
function scoreOf(item, q) {
	if (q === "")
		return 0

	var best = -1
	var codes = item.s || []
	for (var i = 0; i < codes.length; i++) {
		var code = codes[i].split("_").join(" ")
		if (code === q)
			best = Math.max(best, 1000)
		else if (code.indexOf(q) === 0)
			best = Math.max(best, 700 - code.length)
		else if (code.indexOf(q) >= 0)
			best = Math.max(best, 400 - code.length)
	}

	var label = (item.l || "").toLowerCase()
	if (label === q)
		best = Math.max(best, 900)
	else if (label.indexOf(q) === 0)
		best = Math.max(best, 650 - label.length / 4)
	else if (label.indexOf(" " + q) >= 0)
		best = Math.max(best, 500 - label.length / 4)
	else if (label.indexOf(q) >= 0)
		best = Math.max(best, 300 - label.length / 4)

	if (best < 0) {
		var tags = item.t || []
		for (var j = 0; j < tags.length; j++) {
			var tag = tags[j].toLowerCase()
			if (tag === q)
				best = Math.max(best, 250)
			else if (tag.indexOf(q) === 0)
				best = Math.max(best, 200)
		}
	}

	return best
}

// A search also matches the tone qualifier, so "wave tone 2" narrows to the
// toned forms of a tone-capable emoji.
function matchesToneQuery(item, q) {
	if (!item.k)
		return false
	if (q.indexOf("tone") < 0 && q.indexOf("skin") < 0)
		return false
	var label = (item.l || "").toLowerCase()
	var words = q.split(" ")
	for (var i = 0; i < words.length; i++) {
		var word = words[i]
		if (word === "" || word === "tone" || word === "skin" || word === "skin-tone")
			continue
		if (label.indexOf(word) < 0 && word !== "1" && word !== "2" && word !== "3"
				&& word !== "4" && word !== "5")
			return false
	}
	return true
}

// Filters and ranks, best match first. `limit` bounds a typed query, which can
// otherwise pull in hundreds of tag matches.
function search(items, query, limit) {
	var q = normalize(query)
	if (q === "")
		return items.slice(0)

	var hits = []
	for (var i = 0; i < items.length; i++) {
		var score = scoreOf(items[i], q)
		if (score < 0 && matchesToneQuery(items[i], q))
			score = 120
		if (score < 0)
			continue
		hits.push({ item: items[i], score: score, index: i })
	}

	hits.sort(function(a, b) {
		return b.score - a.score || a.index - b.index
	})

	var out = []
	var cap = limit && limit > 0 ? Math.min(limit, hits.length) : hits.length
	for (var k = 0; k < cap; k++)
		out.push(hits[k].item)
	return out
}

// ── skin tones ───────────────────────────────────────────────────────────────

function hasTone(item, tone) {
	return tone >= 0 && item.k && item.k[tone] ? true : false
}

// The character to draw and the value to copy. A tone only applies to the emoji
// that actually have that variant; everything else is left alone.
function displayChar(item, tone) {
	if (hasTone(item, tone))
		return item.k[tone]
	return item.c
}

// ── sections and rows ────────────────────────────────────────────────────────

// Rows for the grid: a header row per section, then rows of `columns` cells.
//
// `index` on a cell row is the position of its first emoji in the flat
// selection order, which is what lets the keyboard find the row to scroll to
// without re-walking the sections.
function buildRows(sections, columns) {
	var rows = []
	var count = 0
	for (var s = 0; s < sections.length; s++) {
		var section = sections[s]
		if (section.label)
			rows.push({ type: "header", label: section.label, index: -1, entries: [] })
		var entries = section.items || []
		for (var i = 0; i < entries.length; i += columns) {
			var slice = entries.slice(i, i + columns)
			rows.push({ type: "cells", label: "", index: count, entries: slice })
			count += slice.length
		}
	}
	return { rows: rows, count: count }
}

// Which row holds a given flat index, so the view can scroll to the selection.
function rowForIndex(rows, index) {
	var found = 0
	for (var i = 0; i < rows.length; i++) {
		var row = rows[i]
		if (row.type !== "cells")
			continue
		if (index >= row.index && index < row.index + row.entries.length)
			return i
		if (row.index <= index)
			found = i
	}
	return found
}

// ── usage ────────────────────────────────────────────────────────────────────

// "Frequently Used" is the emoji picked before, most-used first, capped so it
// stays a page rather than a list.
//
// Usage is recorded per hexcode as { n: picks, t: last pick, ms }. A bare number
// is the shape this file started with and is read as a count with no time, so an
// older state file still works. Most-used leads; time only breaks ties, which is
// what puts the thing you just picked above something used the same number of
// times months ago.
var FREQUENT_LIMIT = 24;

function frequent(items, usage) {
	if (!usage)
		return []

	var scored = []
	for (var i = 0; i < items.length; i++) {
		var raw = usage[items[i].h]
		if (raw === undefined || raw === null)
			continue
		var count = typeof raw === "number" ? raw : (raw.n || 0)
		if (count <= 0)
			continue
		scored.push({
			item: items[i],
			count: count,
			time: typeof raw === "number" ? 0 : (raw.t || 0),
			index: i
		})
	}

	scored.sort(function(a, b) {
		return b.count - a.count || b.time - a.time || a.index - b.index
	})

	var out = []
	for (var k = 0; k < Math.min(FREQUENT_LIMIT, scored.length); k++)
		out.push(scored[k].item)
	return out
}

// ── the model the picker renders ─────────────────────────────────────────────
//
// All of the above, applied. `groupIndex` of -1 means the All tab.
function build(items, query, groupIndex, usage, tone) {
	var q = normalize(query)
	var inGroup = []
	for (var i = 0; i < items.length; i++) {
		if (groupIndex < 0 || items[i].g === groupIndex)
			inGroup.push(items[i])
	}

	if (q !== "")
		return { sections: [{ label: "", items: search(inGroup, q, 500) }], searching: true }

	// The All tab is the history, not the whole set. Landing on 1906 glyphs is
	// what the category tabs are for, and nobody scrolls past the first page of
	// that anyway. Walking off the end of this page drops into the first
	// category (see stepEmojiTab in Launcher.qml).
	if (groupIndex < 0) {
		var used = frequent(items, usage)
		return {
			sections: used.length > 0 ? [{ label: "Frequently Used", items: used }] : [],
			searching: false
		}
	}

	return { sections: [{ label: "", items: inGroup }], searching: false }
}
