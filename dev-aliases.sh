#!/usr/bin/env bash
# dev-aliases.sh — local dev server + cloudflare tunnel, on your clock.
#
#   devup     server + tunnel, port auto-detected (or pass one:  devup 8000)
#   devdown   kill the server + tunnel for that port
#   cc        launch Claude Code with the stack up before and torn down after
#   tunnel    print the current tunnel URL (and re-copy it to the clipboard)
#
# The tunnel URL is copied to the clipboard and opened in the browser once the
# tunnel is actually resolving (so no dead-hostname tabs).
#
# Teardown targets whatever owns the port (lsof), not the npm parent — npm
# doesn't forward signals to the next-server grandchild that holds the socket,
# so killing by port is the only reliable way. Escalates to kill -9. Tunnel is
# killed by tracked PID, never a blanket pkill (which would kill other tunnels).

_dev_detect() {
  local port kind script
  if [ -f package.json ] && grep -q '"dev"[[:space:]]*:' package.json; then
    kind=npm
    script=$(grep -o '"dev"[^,]*' package.json | head -1)
    port=$(echo "$script" | grep -oE -- '(-p|--port)[ =]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    [ -z "$port" ] && { echo "$script" | grep -q vite && port=5173 || port=3000; }
  else
    kind=static; port=8000
  fi
  echo "$port $kind"
}

devup() {
  local detected port kind
  detected="$(_dev_detect)"
  port="${1:-${detected%% *}}"
  kind="${detected##* }"

  local pidfile="/tmp/devstack-$port.pids"
  local cflog="/tmp/cftunnel-$port.log"
  local srvlog="/tmp/devserver-$port.log"

  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found. install it once per machine:  brew install cloudflared"
    return 1
  fi

  # --- server ---
  if lsof -i ":$port" >/dev/null 2>&1; then
    echo "something's already on :$port, leaving it be"
  elif [ "$kind" = npm ]; then
    npm run dev > "$srvlog" 2>&1 &
    echo "$!" >> "$pidfile"
    echo "npm dev server booting on :$port"
  else
    if command -v python3 >/dev/null 2>&1; then
      python3 -m http.server "$port" > "$srvlog" 2>&1 &
    elif command -v npx >/dev/null 2>&1; then
      npx --yes http-server -p "$port" -c-1 . > "$srvlog" 2>&1 &
    else
      echo "need python3 or node to serve static files"; return 1
    fi
    echo "$!" >> "$pidfile"
    echo "static server booting on :$port (serving $(pwd))"
    [ -f index.html ] || echo "  heads up: no index.html here — are you in the right folder?"
  fi

  # --- wait for the server to actually answer (max ~30s) ---
  local i=0
  until curl -s -o /dev/null "http://localhost:$port"; do
    i=$((i+1))
    if [ "$i" -ge 60 ]; then
      echo "server never came up on :$port, NOT opening a tunnel. last log lines:"
      tail -15 "$srvlog" 2>/dev/null
      return 1
    fi
    sleep 0.5
  done
  echo ":$port is live"

  # --- tunnel (only start one if we don't already have a live one here) ---
  if pgrep -f "cloudflared tunnel --url http://localhost:$port" >/dev/null 2>&1; then
    echo "tunnel for :$port already running"
  else
    : > "$cflog"
    nohup cloudflared tunnel --protocol http2 --url "http://localhost:$port" > "$cflog" 2>&1 & disown
    echo "$!" >> "$pidfile"
  fi

  # --- wait for the URL ---
  local url="" j=0
  while [ "$j" -lt 15 ]; do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$cflog" 2>/dev/null | head -1)
    [ -n "$url" ] && break
    sleep 1; j=$((j+1))
  done
  if [ -z "$url" ]; then
    echo "tunnel didn't produce a URL — check $cflog"
    return 1
  fi

  # --- don't hand over a hostname that isn't resolving yet (no NXDOMAIN tabs) ---
  local k=0
  until curl -s -o /dev/null --max-time 3 "$url"; do
    k=$((k+1))
    [ "$k" -ge 15 ] && { echo "tunnel URL not resolving yet, opening anyway: $url"; break; }
    sleep 1
  done

  printf '%s' "$url" > /tmp/tunnel-url
  echo "public URL:  $url"
  command -v pbcopy >/dev/null 2>&1 && printf '%s' "$url" | pbcopy && echo "  (copied to clipboard)"
  command -v open   >/dev/null 2>&1 && open "$url"
}

devdown() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local pidfile="/tmp/devstack-$port.pids"

  # kill the tunnel(s) we started, by tracked PID
  if [ -f "$pidfile" ]; then
    while read -r p; do
      [ -n "$p" ] && kill "$p" 2>/dev/null
    done < "$pidfile"
    rm -f "$pidfile"
  fi

  # kill whatever actually holds the port — catches the next-server grandchild
  # that a parent kill would miss. escalate to -9 if it clings.
  local pids
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill $pids 2>/dev/null && sleep 1
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null

  echo "killed server + tunnel on :$port"
}

tunnel() {
  if [ -s /tmp/tunnel-url ]; then
    cat /tmp/tunnel-url; echo
    command -v pbcopy >/dev/null 2>&1 && printf '%s' "$(cat /tmp/tunnel-url)" | pbcopy
  else
    echo "no tunnel URL recorded — is one running?"
  fi
}

# Launch Claude Code with the stack up before and torn down after.
# No subshell, no trap: `claude` blocks in the current shell, and devdown runs
# when it returns. Teardown fires on /exit, and nothing kills the tunnel while
# you're still working.
cc() {
  local port; port="$(_dev_detect | awk '{print $1}')"
  devup "$port"
  claude "$@"
  devdown "$port"
}
