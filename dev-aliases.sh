#!/usr/bin/env bash
# dev-aliases.sh — local dev server + cloudflare tunnel, on your clock.
# Works in zsh or bash. Source this from your shell rc file.
#
#   devup         server + tunnel on :5173  (or pass a port:  devup 3000)
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
# cc auto-detects the dev port from the project's package.json (3000 Next /
# 5173 Vite), so you don't have to remember which.

devup() {
  local port="${1:-5173}"
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "cloudflared not found. install it first:  brew install cloudflared"
    return 1
  fi
  if lsof -i ":$port" >/dev/null 2>&1; then
    echo "something's already on :$port, leaving it be"
  else
    npm run dev > "/tmp/devserver-$port.log" 2>&1 &
    echo "dev server booting on :$port"
  fi
  if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "a tunnel's already up, not starting another"
  else
    cloudflared tunnel --url "http://localhost:$port" > "/tmp/cftunnel-$port.log" 2>&1 &
  fi
  local url="" i=0
  while [ $i -lt 8 ]; do
    url=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "/tmp/cftunnel-$port.log" 2>/dev/null | head -1)
    [ -n "$url" ] && break
    sleep 1; i=$((i+1))
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
  local port="${1:-5173}"
  local pids
  pids=$(lsof -ti ":$port" 2>/dev/null)
  [ -n "$pids" ] && kill $pids 2>/dev/null
  pkill -f "cloudflared tunnel"
  echo "killed server on :$port + tunnel"
}

# best-effort: read the dev port out of the current project's package.json
_dev_port() {
  local p="" script=""
  if [ -f package.json ]; then
    script=$(grep -o '"dev"[^,]*' package.json | head -1)
    p=$(echo "$script" | grep -oE -- '(-p|--port)[ =]+[0-9]+' | grep -oE '[0-9]+' | head -1)
    if [ -z "$p" ]; then
      echo "$script" | grep -q vite && p=5173 || p=3000
    fi
  fi
  echo "${p:-3000}"
}

# launch Claude Code wrapped in the dev stack: up before, down after, every
# time, no matter how the session starts or how you quit. The subshell + trap
# is what guarantees teardown even on Ctrl-C or a closed window.
cc() {
  local port; port="$(_dev_port)"
  (
    trap "devdown $port" EXIT HUP
    devup "$port"
    claude "$@"
  )
}
