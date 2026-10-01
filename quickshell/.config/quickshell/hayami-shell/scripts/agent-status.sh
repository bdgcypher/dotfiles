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

# The agent this card is about, spelled the way `hayami agent new` titles the
# window it opens. The card's subheading and that window are then the same
# word -- and swapping agents is a change to this one line, rather than to the
# script that already knows what a session is.
PROVIDER="Freebuff"

REFRESH=0
[ "${1:-}" = "--refresh" ] && REFRESH=1

now_ms=$(date +%s)000
# Baré hours, not %H: a leading zero is not a JSON number.
utc_hour=$((10#$(date -u +%H)))

# ── which window belongs to which session ────────────────────────────────────
#
# Every window whose title mentions the provider: the tag `hayami agent new`
# launches with, and the one the TUI keeps in place afterwards. The pid in front
# of each address is the *window's* pid, which is not the CLI's -- see above --
# so the match below walks the process chain rather than trusting it.
#
# One terminal process can hold several of these windows (a tab per session), so
# the pool is consumed as it is handed out: no two sessions ever point at the
# same window. It is refilled per provider, since each looks for its own titles.

provider_windows=""

collect_windows() {
	provider_windows=""
	if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		provider_windows=$(hyprctl clients -j 2>/dev/null |
			jq -r --arg t "$1" '.[]
				| select((((.initialTitle // "") + " " + (.title // "")) | test($t)))
				| "\(.pid) \(.address)"' 2>/dev/null)
	fi
}

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
		addr=$(awk -v p="$p" '$1 == p { print $2; exit }' <<<"$provider_windows")
		if [ -n "$addr" ]; then
			provider_windows=$(grep -Fv " $addr" <<<"$provider_windows")
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
# is for.

sessions='[]'
live=0
model=""
project=""
since=0




# The directory a session works in, shortened to `~` for the home directory: the
# rows and the tooltip are short, and a full path spends most of them on a
# prefix every session here shares. The stripping is a case and not
# `${cwd/#$HOME/~}` because that expansion parses but silently matches nothing
# once the home directory's own slashes are in the pattern.
project_of() {
	case "$1" in
	"$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

# One session onto the reading. Called rather than run in a command
# substitution, because window_for takes its window out of the shared pool.
add_session() { # $1=pid $2=model $3=project $4=status
	local owner="$1" smodel="$2" sproject="$3" sstatus="$4"
	local started address

	started=$(ps -o etimes= -p "$owner" 2>/dev/null | tr -d ' ')
	started="${started:-0}"

	# The first live session is also the single-session reading, so `hayami
	# agent status` still answers "what is the agent doing" without the caller
	# having to know the list exists.
	if [ "$live" = 0 ]; then
		live=1
		model="$smodel"
		project="$sproject"
		since="$started"
	fi

	address=""
	window_for "$owner" && address="$WINDOW"

	sessions=$(jq -c \
		--argjson pid "$owner" --arg model "$smodel" \
		--arg project "$sproject" --argjson since "$started" \
		--arg address "$address" --arg status "$sstatus" \
		'. + [{pid: $pid, model: $model,
			modelShort: ($model | split("/") | last),
			project: $project, since: $since, address: $address,
			status: $status}]' \
		<<<"$sessions")
}

# ── the run state of a lease-backed session ──────────────────────────────────
#
# Which of two states this session is in:
#
#   finished    the turn is over and waiting to be read
#   working     a run is in progress
#
# That is the whole of it. There is deliberately no third state for "the agent is
# blocked on a question", because nothing the CLI writes can tell us that: while
# a question is open the state file is frozen between steps, so the tool call
# and its answer land in a single write and there is no moment at which an
# unanswered call is visible. Measured, not assumed -- AGENTS.md has the numbers
# and the list of what was ruled out.
#
# A *completed* turn is the kind of the last output: `lastMessage` is the value a
# finished run leaves behind and nothing else. `error` is written mid-run as well
# as at the end -- a failed tool call, a cancelled step -- so it is deliberately
# not read as finished, which leaves `working` as the answer for everything else.
#
# The project directory is named after the last segment of the working directory,
# which is the only thing that joins a lease file to a conversation -- the lease
# carries a pid and a model and nothing else -- and the most recently written
# state in it belongs to the session that is up. A session whose project or
# conversation is not there yet reads as working, which is the right answer for a
# session that has just started.
#
# `output` is read with grep rather than jq because the CLI writes the file
# minified with a fixed top-level key order, and `output` is the last of those
# keys but one, so the field is a fixed piece of text in a known place a couple
# of kilobytes from the end -- the tail is read first, with the whole file as the
# fallback for the day it is not there. That keeps this to one grep of a few
# kilobytes per session rather than a parse of a megabyte file, five times a
# minute, for a field that is a fixed piece of text.
#
# The read is of a whole file rather than a torn one, because the CLI writes the
# state to a temporary file and renames it over.

run_state_status() { # $1=the session's cwd
	local cwd="$1" turn_type="" state status="working"

	state=$(find "$CONFIG/projects/${cwd##*/}/chats" -maxdepth 2 -name run-state.json \
		-printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
	if [ -n "$state" ]; then
		turn_type=$(tail -c 4096 "$state" 2>/dev/null |
			grep -o -m1 '"output":{"type":"[a-zA-Z]*"' | head -1 | cut -d'"' -f6)
		[ -n "$turn_type" ] || turn_type=$(grep -o -m1 '"output":{"type":"[a-zA-Z]*"' \
			"$state" 2>/dev/null | head -1 | cut -d'"' -f6)
		[ "$turn_type" = "lastMessage" ] && status="finished"
	fi

	printf '%s\n' "$status"
}

# ── every live session ───────────────────────────────────────────────────────
#
# "Live" is the two-part test: the pid still running *and* the lease unexpired,
# because a crashed CLI leaves its file behind. There is one file per session and
# several can be up at once, each in its own directory, so the reading carries
# all of them and not just the first.

collect_windows "$PROVIDER"

for f in "$CONFIG"/freebuff-live-*.json; do
	[ -f "$f" ] || continue
	owner=$(jq -r '.ownerPid // 0' "$f" 2>/dev/null)
	expires=$(jq -r '.expiresAt // 0' "$f" 2>/dev/null)
	[ "$owner" -gt 0 ] 2>/dev/null || continue
	kill -0 "$owner" 2>/dev/null || continue
	[ "$expires" -gt "$now_ms" ] 2>/dev/null || continue

	cwd=$(readlink -f "/proc/$owner/cwd" 2>/dev/null)
	[ -n "$cwd" ] || continue
	add_session "$owner" \
		"$(jq -r '.model // ""' "$f" 2>/dev/null)" \
		"$(project_of "$cwd")" \
		"$(run_state_status "$cwd")"
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
		# Row order, most urgent first -- the same order the badge picks its
		# colour in, so the top row is always the one the dot is reporting.
		# sort_by is stable, so sessions sharing a state keep the order they
		# were read in.
	def rank: if .status == "working" then 0
	          elif .status == "finished" then 1
	          else 2 end;
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
		| ($list | sort_by(rank)) as $ordered
		# One glyph stands for every session, so what the badge has to say is
		# the most urgent state any of them is in -- a question beats a run under
		# way, and both beat a turn that is merely over.
				| ([$list[] | select(.status == "finished")] | length > 0) as $anyFinished
		| ([$list[] | select(.status == "working")] | length > 0) as $anyWorking
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
			+ (if $anyFinished then "  \u00b7  waiting"
			   else "" end)
				+ (if $fb.balance != null then "  \u00b7  \($fb.daily.remaining)/\($fb.daily.limit) FB"		else "" end)+ (if ($list | length) > 1
			   then "\n" + ([$ordered[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
			   else "" end)
			),
			live: ($live == 1),
			anyFinished: $anyFinished,
			anyWorking: $anyWorking,
			anyWaiting: $anyFinished,
			model: $model,
			modelShort: (if $model == "" then "" else short($model) end),
			project: $project,
			since: $since,
			sessions: $ordered,
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
	# Row order, most urgent first -- see the note on the other copy of this.
	def rank: if .status == "working" then 0
	          elif .status == "finished" then 1
	          else 2 end;
	def directory: if .project == "" then "no directory" else .project end;
	# Priced at nothing rather than left out: the panel reads a rate off every
	# row it draws, and a missing field there is the one shape it cannot render.
	($sessions | map(. + {price: 0, regularPrice: 0, offPeak: false})) as $list
| ($list | sort_by(rank)) as $ordered
| ([$list[] | select(.status == "finished")] | length > 0) as $anyFinished
| ([$list[] | select(.status == "working")] | length > 0) as $anyWorking
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
		+ (if $anyFinished then "  \u00b7  waiting"
		   else "" end)+ (if ($list | length) > 1
		   then "\n" + ([$ordered[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
		   else "" end)
	),
	live: ($live == 1),
	anyFinished: $anyFinished,
	anyWorking: $anyWorking,
	anyWaiting: $anyFinished,
	model: $model,
	modelShort: (if $model == "" then "" else short($model) end),
	project: $project,
	since: $since,
	sessions: $ordered,
		count: ($list | length),
		loggedIn: ($loggedIn == 1),
		balance: 0, dailyLimit: 0, dailySpent: 0, dailyRemaining: 0,
		dailyResetAt: "", wallet: 0, tier: "", streak: 0,
		price: 0, regularPrice: 0, offPeak: false,
		note: (if $loggedIn == 1 then "Freebucks unavailable" else "Not logged in" end)
	}'
