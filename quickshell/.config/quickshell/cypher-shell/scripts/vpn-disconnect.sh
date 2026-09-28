#!/bin/bash

# Hang up whichever tunnel vpn-status.sh reports as up. The popout's one action.
#
# Each client is told in its own terms: Tailscale has a subcommand for this, and
# openconnect is asked to interrupt (SIGINT, the hangup it handles cleanly) --
# there is no globalprotect CLI on this machine to hand the request to, and the
# openconnect process *is* the session.
#
# Exits non-zero only when a tunnel was up and the hangup failed, so the caller
# can tell "nothing to do" from "did not work".

if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
  exec tailscale down
fi

if pgrep -x openconnect >/dev/null 2>&1; then
  pkill -INT -x openconnect
  exit $?
fi

echo "no vpn is up" >&2
exit 0
