#!/bin/bash

# What the bar's agent indicator reads, and what its popout shows: whether an
# agent session is running, which model it is on, and the Freebucks it is
# spending.
#
# Two sources, merged here so the icon and the panel cannot disagree:
#
#   local  ~/.config/manicode/freebuff-live-<pid>.json
#          written by the CLI while a session is live. {instanceId, model,
#          ownerPid, expiresAt}. "Live" needs both halves: the pid still
#          running *and* the lease unexpired, because a crashed CLI leaves the
#          file behind. There is one file per session, and several can be live at
#          once -- each in its own directory -- so the reading carries all of
#          them and not just the first.
#
#   remote www.codebuff.com/api/v1/freebuff/{session,streak}
#          the wallet. Bearer auth with the CLI's own token from
#          ~/.config/manicode/credentials.json. Read-only, and cached below.
#
# The shape is text/alt/tooltip/class with the panel's own fields
# added on, the way vpn-status.sh does it, so the module reads it the same way.
#
# Each session is also matched to its Hyprland window, so the panel can hand the
# focus to it. The window is not found by title alone: the CLI runs under a
# terminal, so the window's pid is an *ancestor* of the session's, not the
# session's own.
#
# Reads no conversation content: never touches message-history.json, and never
# prints the token.
#
#   agent-status.sh            the merged reading
#   agent-status.sh --refresh  ignore the API cache and fetch again

set -uo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/manicode"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hayami-shell"
CACHE="$STATE/agent.json"
CRED="$CONFIG/credentials.json"
API="https://www.codebuff.com"
CACHE_TTL=60

# The interactive `freebuff` TUI opens on this model; the session file carries
# whatever is actually running.
GLYPH=$(printf '\U000F06A9 ')   # nf-md-robot, the same glyph Icons.agent names

# The agent this reading is about, spelled the way its own window title is, so
# the card's subheading and the window you switch to say the same word. It is a
# name and not a guess: an idle shell has no window to read a title from, and a
# provider that only appeared while something was running would come and go.
#
# Changing agents is this one line plus the session file the loop below globs
# for -- nothing else in the script, and nothing in the panel, assumes freebuff.
PROVIDER="Freebuff"

REFRESH=0
[ "${1:-}" = "--refresh" ] && REFRESH=1

now_ms=$(date +%s)000
# Baré hours, not %H: a leading zero is not a JSON number.
utc_hour=$((10#$(date -u +%H)))

# ── which window belongs to which session ────────────────────────────────────
#
# Every window whose title says "Freebuff": the tag `hayami agent new` launches
# with, and the one the TUI keeps in place afterwards. The pid in front of each
# address is the *window's* pid, which is not the CLI's -- see above -- so the
# match below walks the process chain rather than trusting it.
#
# One terminal process can hold several of these windows (a tab per session), so
# the pool is consumed as it is handed out: no two sessions ever point at the
# same window.

freebuff_windows=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
	freebuff_windows=$(hyprctl clients -j 2>/dev/null |
		jq -r '.[]
			| select((((.initialTitle // "") + " " + (.title // "")) | test("Freebuff")))
			| "\(.pid) \(.address)"' 2>/dev/null)
fi

# The window for one session's pid, into $WINDOW, or nothing when it has none --
# a session whose terminal is already gone, or one started outside Hyprland. That
# is a real state and not an error: the panel draws the row either way, and only
# sends the focus to what has a window behind it.
#
# Called in this shell and not in a command substitution, because it takes the
# window it finds out of the pool and a subshell would drop that.
WINDOW=""
window_for() {
	local p="$1" addr
	WINDOW=""
	while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
		addr=$(awk -v p="$p" '$1 == p { print $2; exit }' <<<"$freebuff_windows")
		if [ -n "$addr" ]; then
			freebuff_windows=$(grep -Fv " $addr" <<<"$freebuff_windows")
			WINDOW="$addr"
			return 0
		fi
		p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
	done
	return 1
}

# ── the live sessions (local, cheap) ─────────────────────────────────────────
#
# Every live session, not just the first: several agents can be running in
# different directories at once, and telling them apart is what the panel's list
# is for. "Live" is the same two-part test as before -- the pid still running
# *and* the lease unexpired, because a crashed CLI leaves its file behind.

sessions='[]'
live=0
model=""
project=""
since=0

for f in "$CONFIG"/freebuff-live-*.json; do
	[ -f "$f" ] || continue
	owner=$(jq -r '.ownerPid // 0' "$f" 2>/dev/null)
	expires=$(jq -r '.expiresAt // 0' "$f" 2>/dev/null)
	[ "$owner" -gt 0 ] 2>/dev/null || continue
	kill -0 "$owner" 2>/dev/null || continue
	[ "$expires" -gt "$now_ms" ] 2>/dev/null || continue

	session_model=$(jq -r '.model // ""' "$f" 2>/dev/null)
	cwd=$(readlink -f "/proc/$owner/cwd" 2>/dev/null)
	# `~` for the home directory: the rows and the tooltip are short, and a
	# full path spends most of them on a prefix every session here shares. The
	# stripping is a case and not `${cwd#$HOME}` inside a comparison because
	# `${cwd/#$HOME/~}` does not match -- bash parses the `/#` form but the
	# expanded slashes in the pattern make it silently a no-op.
	session_project="$cwd"
	case "$cwd" in
	"$HOME"/*) session_project="~${cwd#"$HOME"}" ;;
	esac

	# Whether this session is waiting for an answer. The CLI keeps the run's
	# state beside the conversation, and the one field of it worth having is the
	# kind of the last output: `lastMessage` is the value a *completed* run
	# leaves behind, and it is what the bar's dot and the panel's row mean by
	# "waiting".
	#
	# The project directory is named after the last segment of the working
	# directory, which is the only thing that joins a lease file to a
	# conversation -- the lease carries a pid and a model and nothing else -- and
	# the most recently written state in it belongs to the session that is up.
	# A session whose project or conversation is not there yet reports no wait,
	# which is the right answer for a session that has just started.
	#
	# Read with grep rather than jq because the state file is a megabyte or two
	# of message history: the CLI writes it minified with a fixed top-level key
	# order, and `output` is the last of those keys but one, so the one field is
	# a fixed piece of text in a known place. Measured, the marker lands a couple
	# of kilobytes from the end -- what follows it is the output's own value --
	# so the tail is read first and the full file is the fallback for the day it
	# is not there. Either read is a whole file rather than a torn one, because
	# the CLI writes the state to a temporary file and renames it over.
	waiting=false
	turn_type=""
	state=$(find "$CONFIG/projects/${cwd##*/}/chats" -maxdepth 2 -name run-state.json \
		-printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
	if [ -n "$state" ]; then
		turn_type=$(tail -c 4096 "$state" 2>/dev/null |
			grep -o -m1 '"output":{"type":"[a-zA-Z]*"' | head -1 | cut -d'"' -f6)
		[ -n "$turn_type" ] || turn_type=$(grep -o -m1 '"output":{"type":"[a-zA-Z]*"' \
			"$state" 2>/dev/null | head -1 | cut -d'"' -f6)
		# `error` is deliberately not counted as a wait. A snapshot records the
		# run's last output, and a run writes one of those mid-turn as well as
		# at the end -- a failed tool call, a cancelled step -- so treating it
		# as finished would light the dot while the agent is still working.
		[ "$turn_type" = "lastMessage" ] && waiting=true
	fi

	started=$(ps -o etimes= -p "$owner" 2>/dev/null | tr -d ' ')
	started="${started:-0}"

	# The first live session is also the single-session reading, so `hayami agent
	# status` still answers "what is the agent doing" without the caller having to
	# know the list exists.
	if [ "$live" = 0 ]; then
		live=1
		model="$session_model"
		project="$session_project"
		since="$started"
	fi

	address=""
	window_for "$owner" && address="$WINDOW"

	sessions=$(jq -c \
		--argjson pid "$owner" --arg model "$session_model" \
		--arg project "$session_project" --argjson since "$started" \
		--arg address "$address" --argjson waiting "$waiting" \
		'. + [{pid: $pid, model: $model, modelShort: ($model | split("/") | last),
			project: $project, since: $since, address: $address,
			waiting: $waiting}]' \
		<<<"$sessions")
done

# ── the wallet (remote, cached) ──────────────────────────────────────────────

mkdir -p "$STATE"

fresh=0
if [ "$REFRESH" = 0 ] && [ -f "$CACHE" ]; then
	age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
	[ "$age" -lt "$CACHE_TTL" ] && fresh=1
fi

token=$(jq -r '.default.authToken // empty' "$CRED" 2>/dev/null)
logged_in=0
[ -n "$token" ] && logged_in=1

if [ "$fresh" = 0 ] && [ -n "$token" ]; then
	session=$(curl -sS --max-time 5 -H "Authorization: Bearer $token" \
		"$API/api/v1/freebuff/session" 2>/dev/null)
	streak=$(curl -sS --max-time 5 -H "Authorization: Bearer $token" \
		"$API/api/v1/freebuff/streak" 2>/dev/null)

	# Only a well-formed session payload replaces the cache: an error body or a
	# captive-portal page must not overwrite the last good reading.
	if jq -e '.freebucks.balance != null' >/dev/null 2>&1 <<<"$session"; then
		jq -cn --argjson s "$session" --argjson t "${streak:-null}" \
			--arg fetchedAt "$(date +%s)" \
			'{fetchedAt: ($fetchedAt|tonumber), session: $s, streak: $t}' >"$CACHE" 2>/dev/null || true
	else
		# 401 means the token is stale (`freebuff login`); note it and keep what
		# we had rather than blanking the panel.
		if jq -e '.error == "unauthorized"' >/dev/null 2>&1 <<<"$session"; then
			logged_in=0
		fi
	fi
fi

# ── the reading ─────────────────────────────────────────────────────────────

if [ "$logged_in" = 1 ] && [ -f "$CACHE" ]; then
	jq -c \
		--arg glyph "$GLYPH" --arg provider "$PROVIDER" \
		--arg model "$model" --arg project "$project" \
		--argjson live "$live" --argjson since "$since" --argjson sessions "$sessions" \
		--argjson now "$utc_hour" '
		def short($m): ($m | split("/") | last);
		# Whether the off-peak window is open, and what the hour costs. The
		# windows are listed per model, so neither can be decided once for the
		# whole reading: two agents on different models cost different rates.
		def offpeak($fb; $m):
			$fb.offPeak[$m] // null
			| if . == null then null
			  else (($now >= .startHourUtc and $now < .endHourUtc)
				or (.startHourUtc > .endHourUtc and ($now >= .startHourUtc or $now < .endHourUtc)))
			  end;
		def rate($fb; $m):
			if (offpeak($fb; $m) == true) then ($fb.offPeak[$m].price // ($fb.prices[$m] // 0))
			else ($fb.prices[$m] // 0) end;
		def directory: if .project == "" then "no directory" else .project end;
		(.session.freebucks) as $fb
		| ($sessions | map(. + {
				offPeak: (offpeak($fb; .model) == true),
				price: rate($fb; .model),
				regularPrice: ($fb.prices[.model] // 0)
			})) as $list
		# Any session waiting is the dot on the bar: one glyph stands for every
		# session, so one of them wanting an answer is what the badge has to say.
		| ([$list[] | select(.waiting == true)] | length > 0) as $anyWaiting
		| {
			text: $glyph,
			alt: (if $live == 1 then "live" else "idle" end),
			class: (if $live == 1 then "live" else "idle" end),
			provider: $provider,
			# One line per agent once there is more than one: the directory each
			# is working in is the thing that tells them apart.
			tooltip: (
				(if $live == 1 then
					if ($list | length) > 1 then "\($list | length) agents"
					else "Agent: \(short($model))" end
				 else "Agent: idle" end)
				+ (if $anyWaiting then "  \u00b7  waiting" else "" end)
				+ (if $fb.balance != null then "  \u00b7  \($fb.daily.remaining)/\($fb.daily.limit) FB" else "" end)
				+ (if ($list | length) > 1
				   then "\n" + ([$list[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
				   else "" end)
			),
			live: ($live == 1),
			anyWaiting: $anyWaiting,
			model: $model,
			modelShort: (if $model == "" then "" else short($model) end),
			project: $project,
			since: $since,
			sessions: $list,
			count: ($list | length),
			loggedIn: true,
			balance: ($fb.balance // 0),
			dailyLimit: ($fb.daily.limit // 0),
			dailySpent: ($fb.daily.spent // 0),
			dailyRemaining: ($fb.daily.remaining // 0),
			dailyResetAt: ($fb.daily.resetAt // ""),
			wallet: ($fb.wallet.balance // 0),
			tier: (.session.accessTier // ""),
			streak: (.streak.streak // 0),
			price: rate($fb; $model),
			regularPrice: (if $model == "" then 0 else ($fb.prices[$model] // 0) end),
			offPeak: (offpeak($fb; $model) == true),
			note: ""
		}' "$CACHE" 2>/dev/null && exit 0
fi

# No wallet to show -- either not logged in, or the API has never answered. The
# local half is still worth drawing, so the module says what it knows.
jq -cn --arg glyph "$GLYPH" --arg provider "$PROVIDER" \
	--arg model "$model" --arg project "$project" \
	--argjson live "$live" --argjson since "$since" --argjson sessions "$sessions" \
	--argjson loggedIn "$logged_in" '
	def short($m): ($m | split("/") | last);
	def directory: if .project == "" then "no directory" else .project end;
	# Priced at nothing rather than left out: the panel reads a rate off every
	# row it draws, and a missing field there is the one shape it cannot render.
	($sessions | map(. + {price: 0, regularPrice: 0, offPeak: false})) as $list
	| ([$list[] | select(.waiting == true)] | length > 0) as $anyWaiting
	| {
		text: $glyph,
		alt: (if $live == 1 then "live" else "idle" end),
		class: (if $live == 1 then "live" else "idle" end),
		provider: $provider,
		tooltip: (
			(if $live == 1 then
				if ($list | length) > 1 then "\($list | length) agents"
				else "Agent: running" end
			 else "Agent: idle" end)
			+ (if $anyWaiting then "  \u00b7  waiting" else "" end)
			+ (if ($list | length) > 1
			   then "\n" + ([$list[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
			   else "" end)
		),
		live: ($live == 1),
		anyWaiting: $anyWaiting,
		model: $model,
		modelShort: (if $model == "" then "" else short($model) end),
		project: $project,
		since: $since,
		sessions: $list,
		count: ($list | length),
		loggedIn: ($loggedIn == 1),
		balance: 0, dailyLimit: 0, dailySpent: 0, dailyRemaining: 0,
		dailyResetAt: "", wallet: 0, tier: "", streak: 0,
		price: 0, regularPrice: 0, offPeak: false,
		note: (if $loggedIn == 1 then "Freebucks unavailable" else "Not logged in" end)
	}'
