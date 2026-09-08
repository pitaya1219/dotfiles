domain="gui/$UID"

running() {
  # A bootout-ed agent is gone from the domain, so print fails outright; a
  # loaded one that is not running says so on its state line.
  launchctl print "$domain/$1" 2>/dev/null | grep -q "state = running"
}

case "${1:-}" in
  fim)
    start_label=$FIM_LABEL   start_port=$FIM_PORT
    stop_label=$CHAT_LABEL   stop_port=$CHAT_PORT
    ;;
  chat)
    start_label=$CHAT_LABEL  start_port=$CHAT_PORT
    stop_label=$FIM_LABEL    stop_port=$FIM_PORT
    ;;
  status)
    for label in "$CHAT_LABEL" "$FIM_LABEL"; do
      if running "$label"; then echo "$label: running"; else echo "$label: stopped"; fi
    done
    exit 0
    ;;
  *)
    echo "usage: llama-use fim|chat|status" >&2
    exit 2
    ;;
esac

# bootout rather than kill, so that the agents can keep KeepAlive: killing the
# process only makes launchd start it again.
launchctl bootout "$domain/$stop_label" 2>/dev/null || true

# bootout returns before the weights are actually freed, and this machine has
# no room to have both models resident at once, so wait for the port to go
# quiet before asking for the other one.
while curl -sf -o /dev/null --max-time 1 "http://127.0.0.1:$stop_port/health"; do
  sleep 0.2
done

launchctl bootstrap "$domain" "$HOME/Library/LaunchAgents/$start_label.plist" 2>/dev/null || true
launchctl kickstart "$domain/$start_label"

# kickstart returns as soon as the process is spawned, which is several GB of
# weights short of a server that can answer. Callers -- the neovim keymaps in
# particular -- want the endpoint, not the process, so block until /health is
# ok. A cold model takes tens of seconds; a first-ever run has to download it.
curl -sf -o /dev/null --retry 600 --retry-delay 1 --retry-all-errors \
  --retry-connrefused "http://127.0.0.1:$start_port/health"
