#!/usr/bin/env bash
# dev-aliases.sh — local dev server + cloudflare tunnel, on your clock.
# Works in zsh or bash. Source this from your shell rc file.
#
#   devup         server + tunnel, port auto-detected (or pass one:  devup 8000)
#   devdown       kill the server + tunnel on that port
#   cc            launch Claude Code with the stack auto-started before and
#                 auto-killed after. Same behavior on a fresh start OR a resume,
#                 and it tears down no matter how you quit. Args pass straight
#                 through, so:   cc            (fresh)
#                                cc --resume   /  cc --continue   (resume)
#
# When the tunnel comes up, the public URL is copied to your clipboard AND
# shown as a macOS notification, so you never have to dig it out of a log.
#
# Port + server are auto-detected from the project:
#   - package.json with a real "dev" script -> npm run dev  (Next 3000 / Vite 5173)
#   - anything else (plain static frontend)  -> a static server on :8000
# The static server prefers python3, and falls back to `npx http-server` so it
# works the same on a machine that doesn't have python3.

# detect how to serve the current dir. echoes "<port> <kind>":
#   npm    -> package.json has a real "dev" script
#   static -> everything else, served on :8000
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

  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found. install it once per machine:  brew install cloudflared"
    return 1
  fi

  # start the right kind of server, unless something's already on the port
  if lsof -i ":$port" >/dev/null 2>&1; then
    echo "something's already on :$port, leaving it be"
  elif [ "$kind" = npm ]; then
    npm run dev > "/tmp/devserver-$port.log" 2>&1 &
    echo "npm dev server booting on :$port"
  else
    # static frontend: prefer python3 (our convention), fall back to node so
    # this works on a machine without python3 too
    if command -v python3 >/dev/null 2>&1; then
      python3 -m http.server "$port" > "/tmp/devserver-$port.log" 2>&1 &
    elif command -v npx >/dev/null 2>&1; then
      npx --yes http-server -p "$port" -c-1 . > "/tmp/devserver-$port.log" 2>&1 &
    else
      echo "need python3 or node to serve static files"; return 1
    fi
    echo "static server booting on :$port (serving $(pwd))"
    [ -f index.html ] || echo "  heads up: no index.html here — are you in the experiment folder?"
  fi

  # don't open a tunnel until the server actually answers (max ~20s)
  local i=0
  until curl -s -o /dev/null "http://localhost:$port"; do
    i=$((i+1))
    if [ "$i" -ge 40 ]; then
      echo "server never came up on :$port, NOT opening a tunnel. last log lines:"
      tail -15 "/tmp/devserver-$port.log" 2>/dev/null
      return 1
    fi
    sleep 0.5
  done
  echo ":$port is live"

  # now the tunnel has something real behind it
  if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "a tunnel's already up, not starting another"
  else
    cloudflared tunnel --url "http://localhost:$port" > "/tmp/cftunnel-$port.log" 2>&1 &
  fi

  local url="" j=0
  while [ "$j" -lt 10 ]; do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "/tmp/cftunnel-$port.log" 2>/dev/null | head -1)
    [ -n "$url" ] && break
    sleep 1; j=$((j+1))
  done
  if [ -n "$url" ]; then
    echo "public URL:  $url"
    # surface it where the Claude Code UI can't bury it:
    command -v pbcopy >/dev/null 2>&1 && printf '%s' "$url" | pbcopy && echo "  (copied to clipboard)"
    command -v osascript >/dev/null 2>&1 && \
      osascript -e "display notification \"$url\" with title \"Tunnel ready on :$port\" subtitle \"copied to clipboard\"" >/dev/null 2>&1
  else
    echo "tunnel still starting — check /tmp/cftunnel-$port.log in a sec"
  fi
}

devdown() {
  local port="${1:-$(_dev_detect | awk '{print $1}')}"
  local pids
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill $pids 2>/dev/null
  pkill -f "cloudflared tunnel"
  echo "killed server on :$port + tunnel"
}

# launch Claude Code wrapped in the dev stack: up before, down after, every
# time, no matter how the session starts or how you quit. The subshell + trap
# is what guarantees teardown even on Ctrl-C or a closed window.
cc() {
  local port; port="$(_dev_detect | awk '{print $1}')"
  (
    trap "devdown $port" EXIT HUP
    devup "$port"
    claude "$@"
  )
}
