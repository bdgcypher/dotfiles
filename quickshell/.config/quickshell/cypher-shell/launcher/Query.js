.pragma library
.import "Fuzzy.js" as Fuzzy

// Provider wiring for the launcher: which providers a mode queries, the fuzzy
// ranking, and the prefix triggers. These mirror walker's config.toml, which is
// where the keybinds and prefix behaviour are defined today.

// walker config.toml [placeholders]
var PLACEHOLDERS = {
	"default": "  Search...",
	"menus:main": "  Main...",
	"desktopapplications": "  Applications...",
	"clipboard": "  Clipboard History...",
	"symbols": "  Emoji...",
	"emoji": "  Search all emoji...",
	"calc": "  Calculator...",
	"websearch": "  Web Search...",
	"runner": "  Scripts...",
	"files": "  Files...",
	"providerlist": "  Providers...",
	"menus:utilities": "  Utilities...",
	"menus:utilities/capture": "  Capture...",
	"menus:system": "  System...",
	"menus:system/theme": "  Theme...",
	"menus:system:power": "  Power...",
	"menus:system/power": "  Power...",
	"menus:system/config": "  Config...",
	"menus:system/keybinds": "  Keybinds...",
	"menus:system/setup": "  Setup...",
	"menus:system/install": "  Install...",
	"menus:system/remove": "  Remove..."
};

// walker config.toml [providers] empty
//
// What the main view shows before anything is typed. walker keeps this separate
// from `default` on purpose: the main view is the five top-level entries, and
// the nested menus only appear once the query starts filtering, each labelled
// with the menu it lives in (see menuItems() in Launcher.qml). Showing `default`
// here is what made the launcher one long list.
var SET_EMPTY = [
	"menus:main"
];

// walker config.toml [providers] default
var DEFAULT_SET = [
	"menus:main",
	"menus:utilities",
	"menus:utilities/capture",
	"menus:system",
	"menus:system/theme",
	"menus:system/power",
	"menus:system/config",
	"menus:system/setup",
	"desktopapplications"
];

// walker config.toml [[providers.prefixes]]
var PREFIXES = [
	{ prefix: "/", provider: "providerlist" },
	{ prefix: ".", provider: "files" },
	{ prefix: ":", provider: "symbols" },
	{ prefix: "=", provider: "calc" },
	{ prefix: "@", provider: "websearch" },
	{ prefix: "$", provider: "clipboard" }
];

function placeholderFor(mode, override) {
	if (override)
		return override;
	if (PLACEHOLDERS[mode])
		return PLACEHOLDERS[mode];
	return PLACEHOLDERS["default"];
}

// A leading trigger character swaps the provider set, e.g. "=" for the calc.
function resolveQuery(query) {
	for (var i = 0; i < PREFIXES.length; i++) {
		var p = PREFIXES[i];
		if (query.length > 0 && query[0] === p.prefix)
			return { provider: p.provider, text: query.slice(1) };
	}
	return { provider: "", text: query };
}

// Which providers to query, mirroring walker: a fixed provider when -m was
// given, the prefix's provider when the query starts with a trigger, the main
// menu alone while the query is empty, and the whole searchable set once it is
// not.
function providerSetFor(mode, query) {
	if (mode !== "")
		return [mode];

	var resolved = resolveQuery(query);
	if (resolved.provider !== "")
		return [resolved.provider];

	return resolved.text.trim() === "" ? SET_EMPTY : DEFAULT_SET;
}

// ── fuzzy ranking ────────────────────────────────────────────────────────────
//
// walker does not rank anything: elephant does, with fzf's algorithm, and these
// are the same rules its providers use. Fuzzy.js is fzf's FuzzyMatchV2.
//
// Per item, elephant's calcScore():
//
//   1. score each field in order, the best one wins;
//   2. take off the winning field's position in the list -- 5 per field, at most
//      50 -- so a match in the name beats the same match in the comment;
//   3. take off where the match starts, so a match at the front of a field
//      beats the same match later in it. Fuzzy's score has this applied once
//      already; elephant applies it again, and the numbers every MinScore is
//      tuned against have it applied twice, so it is kept;
//   4. floor the result at 10;
//   5. keep the item only if it clears the provider's MinScore, which is what
//      decides how much a query pulls in: 30 for applications, 10 for menus,
//      50 for scripts, 30 for the clipboard.
//
// `fields` and `minScore` are set by whatever builds the item (see Launcher.qml
// and Providers.js); an item with no fields is only ever thresholded.

function fieldsOf(item) {
	if (item.fields)
		return item.fields
	var out = []
	if (item.text) out.push(item.text)
	if (item.subtext) out.push(item.subtext)
	if (item.keywords) out.push(item.keywords)
	return out
}

function clears(item, score) {
	var min = item.minScore === undefined ? 0 : item.minScore
	return item.minScoreInclusive ? score >= min : score > min
}

// Ranks items by how well they match, or by weight alone when the query is
// empty -- which is what walker shows before you type.
function rank(items, query) {
	var needle = query === undefined || query === null ? "" : String(query)

	if (needle === "") {
		var listed = []
		for (var i = 0; i < items.length; i++)
			listed.push({ item: items[i], index: i })
		listed.sort(function(a, b) {
			return (b.item.weight || 0) - (a.item.weight || 0) || a.index - b.index
		})
		var order = []
		for (var j = 0; j < listed.length; j++)
			order.push(listed[j].item)
		return order
	}

	var codes = Fuzzy.codesFor(needle)
	var ranked = []

	for (var n = 0; n < items.length; n++) {
		var item = items[n]

		// Lists that are already the answer -- files behind a path prefix, the
		// calculator, web search -- are shown as produced rather than filtered.
		if (item.always) {
			ranked.push({ item: item, score: 0, index: n })
			continue
		}

		var fields = fieldsOf(item)
		var best = 0
		var bestStart = 0
		var modifier = 0
		for (var k = 0; k < fields.length; k++) {
			if (!fields[k])
				continue
			var res = Fuzzy.score(fields[k], codes)
			if (res === null)
				continue
			if (res.score > best) {
				best = res.score
				bestStart = res.start
				modifier = k
			}
		}
		if (best === 0)
			continue

		var score = Math.max(best - Math.min(modifier * 5, 50) - bestStart, 10)
		if (!clears(item, score))
			continue

		ranked.push({ item: item, score: score, index: n })
	}

	// walker sorts by score descending; equal scores keep the provider's order.
	ranked.sort(function(a, b) { return b.score - a.score || a.index - b.index })

	var out = []
	for (var m = 0; m < ranked.length; m++)
		out.push(ranked[m].item)
	return out
}
