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
#          The lease is tied to the *remote* sponsored slot, not to the local
#          process: the CLI deletes it as soon as the server session stops being
#          `active` (its Ss(), on any other status), so a working session whose
#          slot has lapsed has no lease file at all and used to drop out of the
#          reading entirely -- the badge went dark while the agent was working.
#          found_by_fallback() puts those sessions back.
#
#   local  <project>/chats/<conversation>/log.jsonl
#          the per-step log, and the only local record of a question being
#          asked. See question_state() for what is read out of it.
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
# Reads no conversation content in the ordinary sense: never touches
# message-history.json, and never prints the token. The one exception is spelled
# out where it happens -- title_is_mine() below reads prompt text out of a
# session's own log, and only to answer a yes/no question about which window is
# that session's. The text is compared inside jq and discarded there: it never
# becomes a shell variable, never enters the reading, and is never displayed.
# Nothing new is exposed by it either -- the same text is on the terminal's
# title bar, in the window it is identifying.
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
# Case-insensitively, because the two are not the same string: a terminal left
# on the bare command line keeps the lowercase `freebuff` in its title.
#
# One terminal process can hold several of these windows (a tab per session), so
# the pool is consumed as it is handed out: no two sessions ever point at the
# same window. It is refilled per provider, since each looks for its own titles.
#
# Which window goes to which session is the weak part of this, because every
# tab of a terminal shares that terminal's window pid: walking up from any
# session's process chain lands on the same pid, and the pool was handed out in
# whatever order Hyprland listed the windows. With two sessions that is a coin
# toss, and picking wrong is not cosmetic -- the row you click focuses the wrong
# agent.
#
# The title is what breaks the tie, and it is a real signal rather than a guess:
# it is *evidence of whether the session has spoken yet*. A TUI that has run a
# step rewrites the terminal's title to `Freebuff: <what it is doing>`, and one
# that has not left the title its terminal gave it, which for a session started
# by hand is the bare command name. So the windows sort into two kinds:
#
#   tier 0  the title is exactly the provider   -> a session that has not run a
#           step, which is precisely an `idle` one
#   tier 1  the title starts `Freebuff: `      -> a session the TUI has spoken
#           for
#   tier 2  the title merely mentions it       -> anything else
#
# An idle session takes a tier-0 window and everything else prefers tier 1, so
# the two kinds cannot be swapped whichever order the sessions are read in.
#
# What is left is two sessions of the *same* kind in tabs of one terminal -- two
# working ones, both titled `Freebuff: <their own prompt>`. The tiers cannot
# separate those, but the titles can, because a title is not decoration: the TUI
# puts the prompt in it, and the log records the prompt of every step. So a
# session's own log says which of the candidate titles is its own, and that
# settles it exactly. See title_is_mine(), which is the only thing here that
# reads prompt text and the only thing that does so when this happens.
#
# Every session still falls back to any window its terminal has, because a
# single window has to serve a single session even when its title is tier 0 and
# the session is not idle.

provider_windows=""

# One line per window, tab separated: the window's pid, its address, its tier,
# and its title. The title is carried rather than re-queried because it is the
# only per-session thing Hyprland knows, and the disambiguation below needs it.
collect_windows() {
	provider_windows=""
	if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		provider_windows=$(hyprctl clients -j 2>/dev/null |
			jq -r --arg t "$1" '
			def norm: ascii_downcase | sub("^ +"; "") | sub(" +$"; "");
			.[] | select((((.initialTitle // "") + " " + (.title // "")) | test($t; "i")))
			| ((.title // "") | norm) as $title
			| (if $title == ($t | norm) then 0
			   elif ($title | startswith(($t | norm) + ": ")) then 1
			   else 2 end) as $tier
			| "\(.pid)\t\(.address)\t\($tier)\t\(.title // "")"' 2>/dev/null)
	fi
}

# Is this window titled $2 the one belonging to the session whose log is $1?
#
# The window's title is `<provider>: <prompt>`, truncated to fit, and the log
# records the prompt of every step, so the title is a *prefix* of one of this
# session's prompts and of no other session's. That is the whole test, and it is
# a positive identification: two different sessions do not share a prompt, so
# exactly one candidate can match.
#
# Which way round the comparison runs is deliberate. The needle is the *title*,
# which belongs to Hyprland and is on the terminal's own title bar; the haystack
# is the log. No prompt text is ever lifted out of the log into this shell, and
# grep answers only yes or no. The alternative -- pulling this session's prompts
# out and comparing them to the titles -- puts the user's own text, which can be
# anything they pasted into a message, into shell variables, and buys nothing.
#
# The needle is anchored on the `"prompt":"` that opens the field, so a match has
# to be a prompt and not the same words appearing in a tool result or a file the
# agent read. A prompt containing a quote or a newline is escaped in the log and
# so will not match; that is a miss, and a miss only costs the tier heuristic.
#
# The tail is tried first because it is cheap and usually enough: the title
# carries the last *completed* turn's prompt, so while a turn is running it
# points at the turn before it, whose first step can be megabytes back past
# everything the current turn has logged. Only then is the whole log searched,
# which is a fixed-string scan that stops at the first hit.
title_is_mine() { # $1=session log, $2=window title
	local log="$1" title="$2" lower rest needle
	[ -f "$log" ] || return 1

	# The title is `<provider>: <prompt>`. The provider is dropped by length
	# rather than by pattern, because a prompt may well contain a colon of its
	# own ("fix: the thing") and cutting at the first one would halve it.
	# Lowercased into a copy first: bash applies a case modifier to a substring
	# expansion by ignoring the offsets and handing back the whole string, so
	# `${title,,:0:8}` is not the first eight characters of anything.
	lower="${title,,}"
	rest="$title"
	if [ "${lower:0:${#PROVIDER}}" = "${PROVIDER,,}" ]; then
		rest="${title:${#PROVIDER}}"
		rest="${rest#:}"
		while [ "${rest:0:1}" = " " ]; do rest="${rest:1}"; done
	fi
	# The terminal's own truncation mark, and the space it leaves behind. Done
	# with sed rather than by peeling characters off the end, because the mark
	# is three bytes of UTF-8 and a shell substring counts characters only
	# under a UTF-8 locale -- under LC_ALL=C it would peel one byte and leave
	# two of them behind.
	rest=$(printf '%s' "$rest" | sed 's/[ .…]*$//')
	# Too short to be evidence of anything.
	[ "${#rest}" -ge 12 ] || return 1

	needle="\"prompt\":\"$rest"
	tail -c 262144 "$log" 2>/dev/null | grep -qF -- "$needle" && return 0
	grep -qF -- "$needle" "$log" 2>/dev/null
}

# The window for one session's pid, into $WINDOW, or nothing when it has none --
# a session whose terminal is already gone, or one started outside Hyprland. That
# is a real state and not an error: the panel draws the row either way, and only
# sends the focus to what has a window behind it.
#
# $2 is the tier to prefer: 0 for a session that has not run a step, 1 for one
# that has. $3 is the session's log, used only when the preferred tier leaves
# more than one window to choose between.
#
# Called in this shell and not in a command substitution, because it takes the
# window it finds out of the pool and a subshell would drop that.
WINDOW=""
window_for() { # $1=pid $2=preferred tier $3=session log, may be empty
	local p="$1" want="$2" log="$3"
	local -a cands=()
	local i matched title
	WINDOW=""
	while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
		mapfile -t cands < <(awk -F'\t' -v p="$p" -v w="$want" \
			'$1 == p && $3 == w { print $2 }' <<<"$provider_windows")
		# A single window has to serve a single session whatever its title
		# says, so the preferred tier is a preference and not a requirement.
		[ "${#cands[@]}" -gt 0 ] || mapfile -t cands < <(awk -F'\t' -v p="$p" \
			'$1 == p { print $2 }' <<<"$provider_windows")

		# More than one window of the same kind is two sessions of the same
		# kind in tabs of one terminal, which is the one case the tiers
		# cannot separate. The title can, so ask the session which window is
		# its own. This is the only caller of title_is_mine, and the only
		# place prompt text is read.
		if [ "${#cands[@]}" -gt 1 ] && [ -n "$log" ]; then
			matched=""
			for i in "${!cands[@]}"; do
				title=$(awk -F'\t' -v a="${cands[$i]}" \
					'$2 == a { print $4 }' <<<"$provider_windows")
				if title_is_mine "$log" "$title"; then
					matched="${cands[$i]}"
					break
				fi
			done
			# No match means the title has moved past the log's window or
			# the session is not in this terminal after all; the first
			# candidate is then as good as any.
			cands=("${matched:-${cands[0]}}")
		fi

		if [ "${#cands[@]}" -gt 0 ] && [ -n "${cands[0]}" ]; then
			provider_windows=$(awk -F'\t' -v a="${cands[0]}" \
				'$2 != a' <<<"$provider_windows")
			WINDOW="${cands[0]}"
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

# The pids the lease files named, so the fallback below does not read them twice.
declare -A found_by_lease=()




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
#
# Reads the conversation that resolve_session last resolved, which is the one
# its caller resolved for this very session -- so the status it is handed, the
# log the window is identified from and the window itself are all the same
# conversation. Resolving here as well would be a second, separately-timed
# answer to the same question.
add_session() { # $1=pid $2=model $3=project $4=status
	local owner="$1" smodel="$2" sproject="$3" sstatus="$4"
	local started address tier log=""

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

	# A session that has not run a step is after the window whose title is
	# still the bare provider name; every other session prefers one the TUI has
	# rewritten. See collect_windows for why the title settles it, and what is
	# left over when it cannot.
	address=""
	tier=1
	[ "$sstatus" = "idle" ] && tier=0
	[ -n "$CHAT" ] && log="$CHAT/log.jsonl"
	window_for "$owner" "$tier" "$log" && address="$WINDOW"

	sessions=$(jq -c \
		--argjson pid "$owner" --arg model "$smodel" \
		--arg project "$sproject" --argjson since "$started" \
		--arg address "$address" --arg status "$sstatus" \
		'. + [{pid: $pid, model: $model,
			# A session that has not run a step has no model in its log, and
			# `"" | split("/") | last` is null -- which the row and the
			# tooltip would both render as the word "null".
			modelShort: (if $model == "" then "" else ($model | split("/") | last) end),
			project: $project, since: $since, address: $address,
			status: $status}]' \
		<<<"$sessions")
}

# ── the state of one session ────────────────────────────────────────────────
#
# Four states, which is the whole hierarchy the badge ranks (see the `rank` in
# the reading below, and AGENTS.md):
#
#   waiting     the agent has stopped and will not go on until you answer:
#               either it has asked a question, or the turn ended in an error.
#               Both are the same thing to whoever is looking at the bar -- it is
#               not going to move on its own -- so both get the same state and
#               the same colour, and the badge reports them as one.
#   finished    the turn is over and waiting to be read
#   working     a run is in progress
#   idle        up, and positively doing nothing: at its prompt
#
# waiting outranks finished because it is the only state that is *blocked*, and
# finished outranks working because both mean not-moving while only finished has
# something for you. `idle` wears no dot at all. This is what AGENTS.md used to
# record as undetectable; see question_state() for how it is read now.
#
# The project directory is named after the last segment of the working
# directory, which is the only thing that joins a session to a conversation --
# the lease carries a pid and a model and nothing else -- and the most recently
# written conversation in it belongs to the session that is up. A session with no
# conversation under it at all reads as working, which is the right answer for
# one that has only just started.
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

# The conversation a session is reading, and the state file inside it.
#
# The conversation is the newest one, full stop, and the state is only ever read
# from *inside* it. Getting that wrong is not a subtlety: a session that has not
# run a step has no run-state.json of its own, and preferring "the newest
# conversation that has one" reaches back into a previous, unrelated
# conversation and adopts its turn as this session's. Measured, not guessed --
# opening a session in a directory with history under it painted a red "needs
# input" on an agent that had not been asked a single question, because the
# conversation it borrowed had ended in an error hours earlier.
#
# So the only question is which conversation is current, and the log answers it:
# a session appends to its log for as long as it lives, so the newest log is the
# live conversation. A directory's own mtime is not as good a signal -- it moves
# only when a file appears in it, so a long-running session's directory keeps
# the timestamp of its creation while a rename into an older conversation could
# overtake it.
#
# A session with no log anywhere falls back to the newest conversation of any
# kind, which is one connected for long enough to have not written one.
#
# CHAT is the conversation directory and STATE_FILE the state inside it, which
# is empty when the session has not finished a step yet -- a real and common
# shape, since the CLI creates the conversation and its log on connect and the
# first run-state.json only appears after the first step *ends*. Such a log holds
# no `Start agent` entry, so question_state() calls it `nostart` and it reads as
# `idle`: the honest answer, and the one state that can only be claimed from
# positive evidence.
#
# CHAT and STATE_FILE are globals rather than output because every caller wants
# both, and because the fallback loop reads the log itself.
CHAT=""
STATE_FILE=""

# False only when the project has no conversation under it at all, which is the
# one thing that is not a session: a checkout that was never opened with the
# CLI has no `chats` directory to find.
resolve_session() { # $1=the session's cwd
	local chats="$CONFIG/projects/${1##*/}/chats"

	CHAT=""
	STATE_FILE=""

	# %h is the directory holding the log, which is the conversation.
	CHAT=$(find "$chats" -mindepth 2 -maxdepth 2 -name log.jsonl \
		-printf '%T@ %h\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
	if [ -n "$CHAT" ]; then
		[ -f "$CHAT/run-state.json" ] && STATE_FILE="$CHAT/run-state.json"
		return 0
	fi

	CHAT=$(find "$chats" -mindepth 1 -maxdepth 1 -type d \
		-printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
	[ -n "$CHAT" ]
}

# The kind of the last completed run: `lastMessage`, `error`, or nothing.
turn_kind() { # $1=path to run-state.json
	local state="$1" kind=""
	kind=$(tail -c 4096 "$state" 2>/dev/null |
		grep -o -m1 '"output":{"type":"[a-zA-Z]*"' | head -1 | cut -d'"' -f6)
	[ -n "$kind" ] || kind=$(grep -o -m1 '"output":{"type":"[a-zA-Z]*"' \
		"$state" 2>/dev/null | head -1 | cut -d'"' -f6)
	printf '%s\n' "$kind"
}

# ── is a question open? ─────────────────────────────────────────────────────
#
# `run-state.json` and `chat-messages.json` cannot answer this: while a question
# is open the CLI writes *nothing at all*, so the tool call and its answer land
# in one write and there is no instant at which an unanswered call is on disk.
# Measured, with a watcher over every file under ~/.config/manicode while
# questions were left open -- see AGENTS.md.
#
# `log.jsonl` can. Every step of a run is bracketed by two entries:
#
#   Start agent <model> step N (<run>)
#   End   agent <model> step N (<run>)
#
# `ask_user` does not return until you answer, so a step that asked a question
# is a bracket that stays open for exactly as long as you take to reply. An open
# bracket is therefore "this step has not finished", and the only question is
# what counts as too long.
#
# Measured over one long session (178 steps), the gap is threefold and does not
# overlap:
#
#   ask_user steps   n=8    min 120.5s   p50 339s   max 1559.9s
#   every other step n=170  min   1.3s   p50   6s   max   38.3s
#
# So an open bracket older than the slowest ordinary step is a question. The bar
# is *derived from this log* rather than fixed -- 1.25x the longest non-ask_user
# step recorded here, floored at 45s -- so a machine whose tools are slow raises
# its own bar instead of lighting up on a long build.
#
# The latency IS the threshold: a question is reported one threshold after it is
# asked, which was measured end-to-end at exactly 60s while the floor was 60s.
# Both numbers were pulled as far as the distribution allows. Across 287 ordinary
# steps the slowest was 38.3s (p99 25.0s) and the fastest question ever was
# 120.5s, so the gap is 3x wide; 1.25x on the observed maximum lands at 48s,
# which still sits 2.5x below the fastest question ever seen and 1.25x above the
# slowest tool this machine has ever run. Going lower trades that margin for
# seconds, and the margin is what protects against a future tool that legitimately
# runs for minutes.
#
# A faster signal was looked for and is not there: the CLI's thread wait states
# were sampled throughout an open question and are identical to a normal run's
# (`futex_do_wait` throughout, ids churning, no thread parked on the tty), so
# there is nothing to detect before the clock runs out. `run-state.json` and
# `chat-messages.json` are ruled out above. What is left is the bracket, and how
# long it has been open.
#
# The threshold is what makes this a measurement and not a certainty, and it is
# the one thing here that can be wrong: a tool added in future that legitimately
# runs for minutes would read as a question. It is called out in AGENTS.md for
# that reason. Everything else below is exact.
#
# Cost: a bounded tail of the log (256KB, which is a few thousand steps) rather
# than the whole file, which grows without bound over a long session. Nothing
# outside the tail can change the answer: an open bracket's End, if it ever
# comes, is the next line written after its Start.

question_state() { # $1=path to log.jsonl, $2=path to run-state.json
	local log="$1" state="$2" bracket=""

	# A path that is not a file is no path at all, and a session whose
	# conversation is not on disk yet has neither -- it has only just started,
	# which is what `working` says. Normalised here so the callers can pass
	# whatever resolve_session left them holding.
	[ -f "$log" ] || log=""
	[ -f "$state" ] || state=""
	if [ -z "$log" ] && [ -z "$state" ]; then
		printf 'working\n'
		return 0
	fi

	# The bracket is asked FIRST, and an open one wins outright.
	#
	# It has to: `output.type` is left as `error` by every run that a question
	# interrupted -- the CLI records "the session ended before this response
	# completed" and never clears it until the next turn ends -- so an agent that
	# asked you something an hour ago and has been working ever since still
	# carries one. Reading the error first painted "needs input" on a session that
	# was mid-tool-call, which is the one thing this state must never do. An open
	# step is live truth about right now; the output type is a fact about the
	# last turn to end.
	if [ -f "$log" ]; then
		# One jq pass over the tail: the newest Start, whether an End for that
		# same step has been written since, how long ago the Start was, and the
		# longest step in this log that did *not* ask a question.
		#
		# The threshold is derived here rather than hardcoded, so a machine with
		# slow tools raises its own bar instead of lighting up on a long build.
		# -r because the answer is a bare word, and without it jq hands back a
		# quoted JSON string that would reach the panel as "working" in quotes.
		bracket=$(jq -r -R -s --argjson now "$(date +%s)" '
		def entries: [ split("\n")[] | select(length > 0) | fromjson? | select(. != null) ];
		def isStart: (.msg // "") | startswith("Start agent");
		def isEnd:   (.msg // "") | startswith("End agent");
		def stepno: (.msg // "") | capture("step (?<n>[0-9]+)").n | tonumber;
		# An End that asked a question is exactly the thing we are trying to
		# detect, so it must not be allowed to raise the bar.
		def askedQuestion: ((.data.toolCalls // []) | map(.toolName) | index("ask_user")) != null;
		# The turn terminator, which every run writes when it ends -- including
		# one that was cancelled. It matters because a cancelled step never gets
		# its End: the log goes straight from Start to "Main prompt finished",
		# and that dead bracket would otherwise sit open forever and read as a
		# question nobody is ever going to answer. Measured, not guessed -- a
		# cancelled run here left step 514 open for 80s and lit the badge with
		# no question behind it.
		def turnOver: (.msg // "") == "Main prompt finished";
		# The CLI writes milliseconds ("...:49.645Z") and fromdateiso8601 takes
		# whole seconds only, so the fraction is dropped before parsing -- without
		# this the parse throws and the whole read falls back to "working".
		def epoch: (.timestamp | sub("[.][0-9]+Z$"; "Z") | fromdateiso8601);

		(entries) as $all
		| ([$all[] | select(isStart)] | last) as $start
		| # Zero entries is not the same as no steps. A log that parsed to
		  # nothing at all -- truncated, mid-write, or not this format --
		  # is evidence of *nothing*, and `nostart` below is a claim about
		  # the log: it says every entry was read and none of them began a
		  # step. Without this split the two collapse, and a session whose
		  # log could not be read loses its badge instead of keeping a green
		  # one. `unreadable` is not in the case below, so it falls to the
		  # uncertain reading.
		  if ($all | length) == 0 then "unreadable"
		  elif $start == null then "nostart" else
			($start | stepno) as $step
			# Matched on the step number of the newest Start, so a same-numbered
			# End from an earlier run of the log cannot close this bracket.
			| ([$all[] | select(isEnd) | select(stepno == $step)] | length) as $closed
			# Only a terminator written *after* this Start counts. One from an
			# earlier turn has nothing to do with the step in front of us, and
			# counting those would close every bracket in the log at once.
			| ($all | index($start)) as $at
			| ([$all[$at + 1:][] | select(turnOver)] | length) as $turnEnded
			| ($start | epoch) as $t
			| ($now - $t) as $age
			| 45 as $floor
			| ([$all[] | select(isEnd) | select(askedQuestion | not) | (.data.duration // 0)]
				| (if length > 0 then max else 0 end) / 1000 * 1.25) as $learned
			| ([$floor, $learned] | max) as $threshold
			| if $closed > 0 or $turnEnded > 0 then "closed"
			  elif $age > $threshold then "waiting"
			  else "open" end
		  end
	' < <(tail -c 262144 "$log" 2>/dev/null) 2>/dev/null) || bracket=""
	fi

	case "$bracket" in
	waiting) printf 'waiting\n'; return 0 ;;
	open) printf 'working\n'; return 0 ;;
	esac

	# No step in flight, so the answer is in what the last turn left behind.
	# An errored turn is a question in everything but name: the agent has
	# stopped, and nothing further will happen until you do something about it,
	# so it wears waiting's colour too rather than inventing a fourth.
	if [ -n "$state" ]; then
		case "$(turn_kind "$state")" in
		error) printf 'waiting\n'; return 0 ;;
		lastMessage) printf 'finished\n'; return 0 ;;
		esac
	fi

	# Nothing running, nothing waiting, nothing finished: the session is up and
	# sitting at its prompt. Reported only when the log says so positively --
	# `closed` (every step that began has ended) or `nostart` (the log was read
	# and no step has ever begun in it).
	#
	# Deliberately *not* the fallback for a log that could not be read, in either
	# of the two ways that can happen: `unreadable` (entries were expected and
	# none parsed) and an empty $bracket (jq itself failed, so nothing was
	# learned at all). Claiming "idle" there would silently strip the badge off
	# an agent that is very much working. Uncertainty reads as `working`, which
	# costs a green dot rather than none.
	case "$bracket" in
	closed|nostart) printf 'idle\n' ;;
	*) printf 'working\n' ;;
	esac
}

# One session onto the reading. Called rather than run in a command
# substitution, because window_for takes its window out of the shared pool.

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
	found_by_lease[$owner]=1

	cwd=$(readlink -f "/proc/$owner/cwd" 2>/dev/null)
	[ -n "$cwd" ] || continue
	# Resolved here, once, so the status and the window are read from the same
	# conversation -- and so a session with a lease but no conversation on disk
	# yet is still listed, reading as `working`.
	resolve_session "$cwd"
	add_session "$owner" \
		"$(jq -r '.model // ""' "$f" 2>/dev/null)" \
		"$(project_of "$cwd")" \
		"$(question_state "$CHAT/log.jsonl" "$STATE_FILE")"
done

# Sessions with no lease file, found by walking the process table instead.
#
# The lease is written only while the *remote* sponsored slot is active, and
# removed the moment it is not, so a session that has been running long enough
# for the slot to lapse has no file to find it by -- and it used to vanish from
# the bar entirely while still working, which is the one thing a status badge
# must never do. So the fallback is the process itself: a `freebuff` whose
# working directory has a conversation under it is a session, lease or no lease.
#
# Three things keep this from picking up junk:
#
#   - the executable name, so a subprocess or an unrelated binary called
#     something else is never counted;
#   - the directory having a conversation under it, which is what makes it a
#     conversation rather than any old checkout that happens to be open.
#
# There is deliberately no age check on that conversation. A running process is
# itself the proof of life -- a session that was killed days ago left no process
# to find -- so an age gate here can only ever hide a session that is genuinely
# up, and it hid two: one that had not run a step yet (no state file, written
# only after the first step ends) and one that had been left open on a question
# for days, which writes nothing at all for as long as the question stands. A
# gate that removes false positives it cannot have, at the price of false
# negatives it does, is the wrong way round for a badge.
#
# The model is taken from the newest conversation's log where the log records
# it, and left empty when it does not -- the panel draws the row either way, and
# an empty model is better than a wrong one.

for pid in $(pgrep -x freebuff 2>/dev/null); do
	[ -n "${found_by_lease[$pid]:-}" ] && continue
	# pgrep -x matches the executable name, and the CLI re-execs itself as
	# `freebuff --terminal-command-broker` to run a shell command on the
	# agent's behalf. That one is a tool helper, not a session: it is short
	# lived, it shares the session's directory, and counting it would put a
	# phantom second row in the panel every time a command ran. Only a bare
	# `freebuff` is a session.
	[ "$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" = "freebuff " ] || continue
	cwd=$(readlink -f "/proc/$pid/cwd" 2>/dev/null)
	[ -n "$cwd" ] || continue

	# The conversation, or nothing: a `freebuff` sitting in a directory that has
	# never held a conversation is not a session, and there is nothing to read.
	resolve_session "$cwd" || continue

	model=$(grep -o '"model":"[^"]*"' "$CHAT/log.jsonl" 2>/dev/null |
		tail -1 | cut -d'"' -f4)

	add_session "$pid" "$model" "$(project_of "$cwd")" \
		"$(question_state "$CHAT/log.jsonl" "$STATE_FILE")"
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
		--argjson now "$utc_hour" '		def short($m): (if $m == "" then "" else ($m | split("/") | last) end);# Row order, most urgent first -- the same order the badge picks its
		# colour in, so the top row is always the one the dot is reporting.
		# sort_by is stable, so sessions sharing a state keep the order they
		# were read in.
		def rank: if .status == "waiting" then 0
		          elif .status == "finished" then 1
		          elif .status == "working" then 2
		          else 3 end;
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
		# the most urgent state any of them is in. `waiting` outranks the rest
		# because it is the only state that is *stopped*: a working session is
		# going to do the next thing by itself, and a finished one has already
		# done everything it was asked to, but nothing at all will happen to a
		# waiting one until you answer it.
		| ([$list[] | select(.status == "waiting")] | length > 0) as $anyWaiting
		| ([$list[] | select(.status == "finished")] | length > 0) as $anyFinished
		| ([$list[] | select(.status == "working")] | length > 0) as $anyWorking
		| ([$list[] | select(.status == "idle")] | length > 0) as $anyIdle
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
			+ (if $anyWaiting then "  \u00b7  needs input"
			   else "" end)
			+ (if $anyFinished then "  \u00b7  finished"
			   else "" end)
				+ (if $fb.balance != null then "  \u00b7  \($fb.daily.remaining)/\($fb.daily.limit) FB"		else "" end)+ (if ($list | length) > 1
			   then "\n" + ([$ordered[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
			   else "" end)
			),live: ($live == 1),
			anyWaiting: $anyWaiting,
			anyFinished: $anyFinished,
			anyWorking: $anyWorking,
			anyIdle: $anyIdle,
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
	def short($m): (if $m == "" then "" else ($m | split("/") | last) end);
	# Row order, most urgent first -- see the note on the other copy of this.
	def rank: if .status == "waiting" then 0
	          elif .status == "finished" then 1
	          elif .status == "working" then 2
	          else 3 end;
	def directory: if .project == "" then "no directory" else .project end;
	# Priced at nothing rather than left out: the panel reads a rate off every
	# row it draws, and a missing field there is the one shape it cannot render.
	($sessions | map(. + {price: 0, regularPrice: 0, offPeak: false})) as $list
| ($list | sort_by(rank)) as $ordered
| ([$list[] | select(.status == "waiting")] | length > 0) as $anyWaiting
| ([$list[] | select(.status == "finished")] | length > 0) as $anyFinished
| ([$list[] | select(.status == "working")] | length > 0) as $anyWorking
| ([$list[] | select(.status == "idle")] | length > 0) as $anyIdle
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
		+ (if $anyWaiting then "  \u00b7  needs input"
		   else "" end)
		+ (if $anyFinished then "  \u00b7  finished"
		   else "" end)+ (if ($list | length) > 1
		   then "\n" + ([$ordered[] | "\(directory)  \u00b7  \(.modelShort)"] | join("\n"))
		   else "" end)
	),
	live: ($live == 1),
	anyWaiting: $anyWaiting,
	anyFinished: $anyFinished,
	anyWorking: $anyWorking,
	anyIdle: $anyIdle,
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
