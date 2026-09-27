.pragma library

// Item builders for the providers beyond menus and desktop applications.
//
// Every builder returns the same shape the ranking code expects:
//   { text, fields, minScore, subtext, icon, weight, kind, ...extra }
// `fields` is the ordered list the query is matched against and `minScore` the
// threshold it has to clear -- together they are elephant's calcScore and its
// provider's MinScore, and they are what decides how much a query pulls in (see
// Query.js). `always` marks a list that is already the answer and is shown as
// produced. `kind` decides what activating the item does, which is handled in
// Launcher.qml (it needs Quickshell for exec, so it cannot live here).

// elephant's websearch plugin builds Google URLs -- this URL template is the one
// found in its plugin binary (https://www.google.com/search?q=%TERM%).
var WEBSEARCH_URL = "https://www.google.com/search?q=%TERM%";

// Providers this launcher can actually answer with, for the "/" provider list.
// Unimplemented elephant plugins (bluetooth, windows, snippets, ...) are left
// out on purpose: listing them would only produce empty results.
var BUILTIN_PROVIDERS = [
	{ name: "desktopapplications", label: "Applications" },
	{ name: "clipboard", label: "Clipboard History" },
	{ name: "runner", label: "Scripts" },
	{ name: "symbols", label: "Emoji" },
	{ name: "calc", label: "Calculator" },
	{ name: "files", label: "Files" },
	{ name: "websearch", label: "Web Search" }
];

function encodeQuery(text) {
	return encodeURIComponent(text)
}

function isFileUriList(text) {
	if (!text)
		return false
	var lines = text.split("\n")
	var seen = 0
	for (var i = 0; i < lines.length; i++) {
		var line = lines[i].trim()
		if (line === "")
			continue
		if (line.indexOf("file://") !== 0)
			return false
		seen++
	}
	return seen > 0
}

// ── Scripts (elephant's runner) ──────────────────────────────────────────────

// elephant's runner provider scores the binary name (then its alias) with
// MinScore 50, the strictest of any provider -- typing part of a command name
// is meant to give you that command, not everything that echoes it.
function runnerItems(list) {
	var out = []
	for (var i = 0; i < (list ? list.length : 0); i++) {
		out.push({
			text: list[i].text,
			fields: [list[i].text],
			minScore: 50,
			subtext: list[i].path,
			keywords: "",
			icon: "",
			weight: 0,
			kind: "runner",
			path: list[i].path
		})
	}
	return out
}

// ── Emoji (elephant's symbols) ───────────────────────────────────────────────

// Both this and the picker read the same vendored dataset, so a name found by
// the ":" prefix in the list is the name the grid shows. The shortcodes go into
// the keywords, which is what makes ":+1", ":thumbsup" and "thumbs up" all find
// the same entry. Thresholded at 0 rather than elephant's 50 for symbols: the
// list is the flat view of a dataset you are already searching by hand, and the
// grid, not this, is the picker.
function symbolItems(items) {
	var out = []
	for (var i = 0; i < (items ? items.length : 0); i++) {
		var item = items[i]
		var codes = item.s || []
		var keywords = codes.join(" ")
		out.push({
			text: item.l,
			fields: [item.l, keywords],
			minScore: 0,
			subtext: codes.length > 0 ? ":" + codes[0] + ":" : "",
			keywords: keywords,
			icon: item.c,
			weight: 0,
			kind: "symbol",
			value: item.c
		})
	}
	return out
}

// ── Clipboard history ────────────────────────────────────────────────────────

// Entries are either a plain string (text, which is how the store started) or an
// object describing an image the watcher saved. Both shapes live in the same
// file and both are shown in the same list.

function isImageEntry(value) {
	return value && typeof value === "object" && value.type === "image"
}

function humanSize(bytes) {
	if (!bytes)
		return ""
	if (bytes < 1024)
		return bytes + " B"
	if (bytes < 1024 * 1024)
		return Math.round(bytes / 1024) + " KB"
	return (Math.round(bytes / (1024 * 1024) * 10) / 10) + " MB"
}

// elephant's clipboard provider scores the entry's content with MinScore 30.
// The first line is the row's label and the whole entry is the second field, so
// a multi-line clip is still found by anything inside it.
function clipboardItems(history) {
	var out = []
	for (var i = 0; i < (history ? history.length : 0); i++) {
		var value = history[i]

		if (isImageEntry(value)) {
			var dimensions = value.w && value.h ? value.w + " \u00d7 " + value.h : ""
			var size = humanSize(value.bytes)
			var detail = [dimensions, size].filter(function(part) { return part !== "" }).join(" \u00b7 ")
			var imageWords = "image picture screenshot clipboard " + detail + " " + (value.mime || "")
			out.push({
				text: "Image",
				fields: ["Image", imageWords],
				minScore: 30,
				// The dimensions ride on the row's second line rather than in the
				// preview pane: the pane is busy showing the image itself, and the
				// row is what you read while scrolling. `path` is the same two-line
				// slot the menu paths use.
				path: detail,
				subtext: "",
				keywords: imageWords,
				icon: "",
				weight: 0,
				kind: "clipboard-image",
				image: value.file,
				mime: value.mime || "image/png",
				value: value.file
			})
			continue
		}

		var full = String(value)
		var firstLine = full.split("\n")[0]
		out.push({
			text: firstLine,
			fields: full.length > firstLine.length ? [firstLine, full] : [firstLine],
			minScore: 30,
			// The full entry, so multi-line and file lists are visible before
			// you pick them.
			subtext: full.length > firstLine.length ? full : "",
			keywords: "",
			icon: "",
			weight: 0,
			kind: "clipboard",
			value: value
		})
	}
	return out
}

// ── Files (the "." prefix) ───────────────────────────────────────────────────

// list-dir.py already filters by the typed prefix, so these are shown as-is
// rather than ranked: a partial path is not a fuzzy match.
function fileItems(payload) {
	var out = []
	var entries = payload && payload.entries ? payload.entries : []
	for (var i = 0; i < entries.length; i++) {
		out.push({
			text: entries[i].name + (entries[i].dir ? "/" : ""),
			always: true,
			subtext: entries[i].path,
			keywords: "",
			icon: entries[i].dir ? "\uF115" : "\uF15B",
			weight: 0,
			kind: "file",
			path: entries[i].path,
			isDir: entries[i].dir
		})
	}
	return out
}

// ── Calculator (the "=" prefix, via qalc) ────────────────────────────────────

// One entry, made from the query, so there is nothing to filter.
function calcItems(expression, result) {
	if (!result)
		return []
	return [{
		text: expression + " = " + result,
		always: true,
		subtext: "select to copy",
		keywords: "",
		icon: "",
		weight: 0,
		kind: "calc",
		value: result
	}]
}

// ── Web search (the "@" prefix, and -m websearch) ────────────────────────────

// Made from the query, so it always matches it.
function websearchItems(term) {
	var query = (term || "").trim()
	if (query === "")
		return []
	return [{
		text: "Search the web for \"" + query + "\"",
		always: true,
		subtext: WEBSEARCH_URL.replace("%TERM%", encodeQuery(query)),
		keywords: "",
		icon: "",
		weight: 0,
		kind: "websearch",
		url: WEBSEARCH_URL.replace("%TERM%", encodeQuery(query))
	}]
}

// ── Provider list (the "/" prefix) ───────────────────────────────────────────

// The provider's name, then its label, so "app" and "clipboard" both find the
// entry. Thresholded at 0: there are only a dozen, and this list is the one
// place you look for something you cannot name.
function providerListItems(menuNames, menus) {
	var out = []

	for (var i = 0; i < BUILTIN_PROVIDERS.length; i++) {
		out.push({
			text: BUILTIN_PROVIDERS[i].name,
			fields: [BUILTIN_PROVIDERS[i].name, BUILTIN_PROVIDERS[i].label],
			minScore: 0,
			subtext: BUILTIN_PROVIDERS[i].label,
			keywords: "",
			icon: "",
			weight: 0,
			kind: "provider",
			provider: BUILTIN_PROVIDERS[i].name
		})
	}

	for (var j = 0; j < (menuNames ? menuNames.length : 0); j++) {
		var name = "menus:" + menuNames[j]
		var menu = menus ? menus[menuNames[j]] : null
		var pretty = menu ? menu.pretty : ""
		out.push({
			text: name,
			fields: [name, pretty],
			minScore: 0,
			subtext: pretty,
			keywords: "",
			icon: "",
			weight: 0,
			kind: "provider",
			provider: name
		})
	}

	return out
}
