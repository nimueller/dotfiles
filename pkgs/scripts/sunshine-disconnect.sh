# shellcheck shell=bash
# Built with writeShellApplication (pkgs/default.nix), which adds the shebang
# End the Sunshine stream: closes the running app over Sunshine's web API,
# which disconnects the client (the power menu, quickshell/menus/power.qml).
# The API wants the web UI's login, which lives in the keyring as
# "user:password":
#   secret-tool store --label='Sunshine web UI' service sunshine
close_url=https://localhost:47990/api/apps/close
store_command="secret-tool store --label='Sunshine web UI' service sunshine"

notify() {
    notify-send -a Sunshine "$@"
}

if ! login=$(secret-tool lookup service sunshine); then
    notify 'No login for Sunshine' \
        "Store the web UI's login in the keyring: $store_command, then enter user:password."
    exit 1
fi

credentials=$(printf %s "$login" | base64 -w0)
# The header goes through stdin, so the password stays out of the process list;
# -k: Sunshine's certificate is its own
if ! printf 'Authorization: Basic %s\n' "$credentials" |
    curl -fsSk -o /dev/null -X POST -H @- "$close_url"; then
    notify "Couldn't end the stream" 'Is Sunshine running, and is the login in the keyring right?'
    exit 1
fi
