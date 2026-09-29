#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
username=${1:-admin}
case "$username" in
    ''|*[!a-zA-Z0-9_-]*) echo 'Username must contain only letters, digits, _ or -.' >&2; exit 1 ;;
esac

if [ -e .secrets/auth/.htpasswd ]; then
    echo 'Authentication already exists; see README.md to change a password.' >&2
    exit 1
fi

umask 077
mkdir -p .secrets/auth
chmod 700 .secrets
chmod 755 .secrets/auth
password=$(openssl rand -hex 18)
temp_file=$(mktemp .secrets/auth/.htpasswd.XXXXXX)
trap 'rm -f "$temp_file"' EXIT HUP INT TERM

if command -v htpasswd >/dev/null 2>&1; then
    printf '%s\n' "$password" | htpasswd -niB "$username" > "$temp_file"
else
    printf '%s\n' "$password" | docker run --rm -i httpd:2.4-alpine htpasswd -niB "$username" > "$temp_file"
fi
test -s "$temp_file"
chmod 644 "$temp_file"
mv "$temp_file" .secrets/auth/.htpasswd
printf 'Username: %s\nPassword: %s\n' "$username" "$password" > .secrets/credentials.txt
echo 'Authentication initialized. Login details: .secrets/credentials.txt'
