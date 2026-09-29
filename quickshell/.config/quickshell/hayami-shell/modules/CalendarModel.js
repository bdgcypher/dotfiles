.pragma library

// Pure date arithmetic for the clock's calendar: no Qt, no locale, no state.
//
// Everything the panel needs to *draw* lives here so the panel itself is only
// layout, and so the awkward parts -- a month grid that starts on an arbitrary
// weekday, week numbers that belong to ISO weeks rather than to the row, a year
// measured in whole days -- can be reasoned about on their own.
//
// The shapes follow Omarchy's clock plugin (MIT), which is where this panel
// comes from: six fixed rows so the popup is the same height in February as in
// August, week numbers numbered by the ISO week owning the row's Thursday, a
// week start that falls back to the locale's own, and a life rail measured from
// a birth year rather than an age so it keeps counting on its own.

var MS_PER_DAY = 86400000

// Weekday indices match both Date.getDay() and QML's Locale.Sunday…Saturday, so
// a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday",
	"friday", "saturday"]

function pad2(value) {
	var n = Number(value)
	return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared against
// today without dragging Date objects through bindings.
function dateKey(year, month, day) {
	return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
	return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

// ── the week's start ─────────────────────────────────────────────────────────
//
// Stored by name ("monday") rather than by index: the state file is meant to be
// readable, and the name is the thing the tooltip promises to switch to.

// A configured week start as a weekday index, or null when the value is missing
// or is nonsense. Numbers are taken as indices, names by their first three
// letters, so "mon", "Monday" and 1 all mean the same day.
function coerceWeekStart(value) {
	if (value === undefined || value === null)
		return null
	if (typeof value === "number")
		return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null
	var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
	if (text === "")
		return null
	for (var i = 0; i < WEEKDAY_NAMES.length; i++) {
		if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text)
			return i
	}
	var parsed = parseInt(text, 10)
	return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// The week start to draw with: what was chosen, otherwise the locale's own,
// otherwise Monday. An unset preference follows the locale rather than being
// pinned, so a fresh install starts out matching the rest of the desktop.
function normalizedWeekStart(value, fallback) {
	var configured = coerceWeekStart(value)
	if (configured !== null)
		return configured
	var fallbackStart = coerceWeekStart(fallback)
	return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
	return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch between --
// Monday and Sunday. A calendar set to any other start (Saturday, say) is drawn
// as it is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
	return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

// The seven weekday indices in the order the grid draws them, left to right.
function weekdayOrder(weekStart) {
	var start = normalizedWeekStart(weekStart, 1)
	var out = []
	for (var i = 0; i < 7; i++)
		out.push((start + i) % 7)
	return out
}

// ── ISO weeks and the year ───────────────────────────────────────────────────

// ISO-8601 week number: the week owning the Thursday of that date's Monday-based
// week.
function isoWeek(year, month, day) {
	var date = new Date(Date.UTC(year, month, day))
	var weekday = date.getUTCDay() || 7
	date.setUTCDate(date.getUTCDate() + 4 - weekday)
	var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
	return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
	return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
	return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in the
// year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
	var total = daysInYear(year)
	if (total <= 0)
		return 0
	return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
	return Math.round(yearProgress(year, month, day) * 100)
}

// ── the life rail ────────────────────────────────────────────────────────────
//
// Memento mori, and the reason the rail is measured from a birth *year* rather
// than an age: a year keeps counting on its own instead of going stale the
// moment it is entered. The default expectancy is a round number rather than
// anything from an actuarial table -- the point is the reminder, not the
// arithmetic, and the number is a setting.

var DEFAULT_LIFE_EXPECTANCY = 90

// 0 means "not set", which is also what blank, malformed, future and
// implausibly distant years all mean.
function parseBirthYear(value, currentYear) {
	var now = Math.round(Number(currentYear))
	if (!isFinite(now))
		return 0
	var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
	if (!/^\d{4}$/.test(text))
		return 0
	var year = parseInt(text, 10)
	if (!isFinite(year) || year > now || year < now - 120)
		return 0
	return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for all
// of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
	var born = parseBirthYear(birthYear, currentYear)
	if (born <= 0)
		return 0
	return Math.round(Number(currentYear)) - born
}

// Unset or nonsense falls back to the default rather than to zero, so the rail
// always has something to measure against.
function parseLifeExpectancy(value) {
	var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
	if (!/^\d+$/.test(text))
		return DEFAULT_LIFE_EXPECTANCY
	var years = parseInt(text, 10)
	if (!isFinite(years) || years <= 0 || years > 150)
		return DEFAULT_LIFE_EXPECTANCY
	return years
}

function lifeProgress(age, expectancy) {
	var years = Math.round(Number(age))
	var span = parseLifeExpectancy(expectancy)
	if (!isFinite(years) || years <= 0 || span <= 0)
		return 0
	return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
	return Math.round(lifeProgress(age, expectancy) * 100)
}

// ── the grid ─────────────────────────────────────────────────────────────────

// Always six rows of seven days. A fixed grid keeps the popup exactly the same
// height in every month, so stepping through the year never makes the panel jump
// under the pointer.
//
// Each day carries what the cell draws by: whether it belongs to the month on
// screen, whether it is a weekend, and whether it is today. Each row carries its
// week number, taken from the ISO week owning that row's Thursday -- which is
// the definition itself for Monday-start weeks, and the only answer that stays
// stable for the other starts, where a row straddles two ISO weeks but shares
// all of Monday through Thursday with one of them.
function monthGrid(year, month, weekStart, todayKey) {
	var start = normalizedWeekStart(weekStart, 1)
	var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
	var cursor = new Date(year, month, 1 - leading)
	var today = String(todayKey || "")
	var weeks = []

	for (var w = 0; w < 6; w++) {
		var days = []
		var thursday = null
		for (var d = 0; d < 7; d++) {
			var cellYear = cursor.getFullYear()
			var cellMonth = cursor.getMonth()
			var cellDay = cursor.getDate()
			var weekday = cursor.getDay()
			var key = dateKey(cellYear, cellMonth, cellDay)
			if (weekday === 4)
				thursday = { year: cellYear, month: cellMonth, day: cellDay }
			days.push({
				key: key,
				day: cellDay,
				weekday: weekday,
				inMonth: cellMonth === month && cellYear === year,
				weekend: weekday === 0 || weekday === 6,
				today: key === today
			})
			cursor.setDate(cursor.getDate() + 1)
		}
		var anchor = thursday || days[0]
		weeks.push({
			week: isoWeek(anchor.year, anchor.month, anchor.day),
			days: days
		})
	}
	return weeks
}

// The month `delta` months away from this one, as { year, month }.
function stepMonth(year, month, delta) {
	var target = new Date(year, Number(month) + Number(delta), 1)
	return { year: target.getFullYear(), month: target.getMonth() }
}
