#!/usr/bin/env bash
# dev-aliases.sh — local dev server + cloudflare tunnel, on your clock.
#
#   devup     server + tunnel, port auto-detected (or pass one:  devup 8000)
#   devdown   kill the server + tunnel for that port
#   cc        launch Claude Code with the stack up before and torn down after
#   tunnel    print the current tunnel URL (optionally per port: tunnel 8000)
#
# Tunnels always use --protocol http2. QUIC (the cloudflared default) fails on
# some wired networks: the tunnel registers fine but the hostname never becomes
# publicly resolvable. http2 rides TCP and works everywhere.
#
# The tunnel is launched detached (nohup + disown) so the Claude Code session
# can't signal it, and teardown is PID-tracked so we never blanket-kill a tunnel
# belonging to another project.

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
  local urlfile="/tmp/tunnel-url-$port"

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

  # --- tunnel ---
  # Only count tunnels THIS devup started (tracked in the pidfile). A stray
  # cloudflared started by something else (e.g. Claude Code) must not suppress
  # ours — theirs is likely QUIC and therefore dead on this network.
  local mine=""
  if [ -f "$pidfile" ]; then
    while read -r p; do
      [ -n "$p" ] && ps -p "$p" -o command= 2>/dev/null | grep -q cloudflared && mine="$p"
    done < "$pidfile"
  fi

  if [ -n "$mine" ]; then
    echo "tunnel for :$port already running (pid $mine)"
  else
    # warn about foreign tunnels so a stale one doesn't confuse the URL
    local foreign
    foreign=$(pgrep -f "cloudflared tunnel.*localhost:$port" 2>/dev/null | tr '\n' ' ')
    [ -n "$foreign" ] && echo "  note: other cloudflared on :$port ($foreign) — run devdown $port to clear"

    : > "$cflog"
    nohup cloudflared tunnel --protocol http2 --url "http://localhost:$port" > "$cflog" 2>&1 & disown
    echo "$!" >> "$pidfile"
  fi

  # --- wait for the URL ---
  local url="" j=0
  while [ "$j" -lt 15 ]; do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$cflog" 2>/dev/null | tail -1)
    [ -n "$url" ] && break
    sleep 1; j=$((j+1))
  done
  if [ -z "$url" ]; then
    echo "tunnel didn't produce a URL — check $cflog"
    return 1
  fi

  # --- don't hand over a hostname that isn't resolving yet ---
  local host k=0
  host="${url#https://}"
  until nslookup "$host" >/dev/null 2>&1; do
    k=$((k+1))
    [ "$k" -ge 20 ] && { echo "tunnel URL not resolving yet, opening anyway: $url"; break; }
    sleep 1
  done

  printf '%s' "$url" > "$urlfile"
  echo "public URL:  $url"
  command -v pbcopy >/dev/null 2>&1 && printf '%s' "$url" | pbcopy && echo "  (copied to clipboard)"
  command -v open   >/dev/null 2>&1 && open "$url"
}

devdown() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local pidfile="/tmp/devstack-$port.pids"

  # kill what we started, by tracked PID
  if [ -f "$pidfile" ]; then
    while read -r p; do
      [ -n "$p" ] && kill "$p" 2>/dev/null
    done < "$pidfile"
    rm -f "$pidfile"
  fi

  # kill any OTHER cloudflared pointed at this port (orphans from elsewhere).
  # Scoped to the port, so a tunnel for another project is never touched.
  pkill -f "cloudflared tunnel.*localhost:$port" 2>/dev/null

  # kill whatever actually holds the port — catches the next-server grandchild
  # that a parent kill would miss. escalate to -9 if it clings.
  local pids
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill $pids 2>/dev/null && sleep 1
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null

  rm -f "/tmp/tunnel-url-$port"
  echo "killed server + tunnel on :$port"
}

tunnel() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local urlfile="/tmp/tunnel-url-$port"
  if [ -s "$urlfile" ]; then
    cat "$urlfile"; echo
    command -v pbcopy >/dev/null 2>&1 && printf '%s' "$(cat "$urlfile")" | pbcopy
  else
    echo "no tunnel URL recorded for :$port — is one running?"
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
