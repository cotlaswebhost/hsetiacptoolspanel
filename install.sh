#!/usr/bin/env bash
set -euo pipefail

PANEL_DIR="${PANEL_DIR:-/usr/local/olspanel/mypanel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/payload/mypanel"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="${BACKUP_ROOT:-/root/hsetiacptoolspanel-backups}"
BACKUP_DIR="$BACKUP_ROOT/$TS"

REQUIRED_FILES=(
  "users/database.py"
  "whm/views.py"
  "whm/templates/whm/backup_restore.html"
)

log() {
  printf '[hestia-olspanel] %s\n' "$*"
}

fail() {
  printf '[hestia-olspanel] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    fail "Run as root."
  fi
}

check_paths() {
  [[ -d "$PANEL_DIR" ]] || fail "OLSPanel path not found: $PANEL_DIR"
  [[ -d "$PAYLOAD_DIR" ]] || fail "Payload path not found: $PAYLOAD_DIR"

  for rel in "${REQUIRED_FILES[@]}"; do
    [[ -f "$PAYLOAD_DIR/$rel" ]] || fail "Missing payload file: $PAYLOAD_DIR/$rel"
    [[ -f "$PANEL_DIR/$rel" ]] || fail "Missing target file: $PANEL_DIR/$rel"
  done
}

backup_targets() {
  mkdir -p "$BACKUP_DIR"
  log "Creating backup in $BACKUP_DIR"

  for rel in "${REQUIRED_FILES[@]}"; do
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$PANEL_DIR/$rel" "$BACKUP_DIR/$rel"
  done

  log "Backup complete"
}

deploy_files() {
  log "Deploying Hestia restore files"

  for rel in "${REQUIRED_FILES[@]}"; do
    install -D -m 0644 "$PAYLOAD_DIR/$rel" "$PANEL_DIR/$rel"
  done

  if id -u www-data >/dev/null 2>&1; then
    chown www-data:www-data "$PANEL_DIR/users/database.py" || true
    chown www-data:www-data "$PANEL_DIR/whm/views.py" || true
    chown www-data:www-data "$PANEL_DIR/whm/templates/whm/backup_restore.html" || true
  fi
}

run_checks() {
  log "Running syntax and Django checks"
  cd "$PANEL_DIR"

  python3 -m py_compile users/database.py

  if [[ -x /root/venv/bin/python ]]; then
    /root/venv/bin/python manage.py check
  else
    python3 manage.py check
  fi
}

restart_services() {
  log "Restarting services"
  systemctl restart cp
  systemctl is-active --quiet cp || fail "cp service is not active after restart"

  # Different hosts use different service names for OpenLiteSpeed.
  systemctl restart lsws 2>/dev/null || systemctl restart openlitespeed 2>/dev/null || true
}

health_checks() {
  log "Running panel health checks"

  code_backend="$(curl -k -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ || true)"
  code_login="$(curl -k -s -o /dev/null -w '%{http_code}' https://127.0.0.1:2083/login/ || true)"

  [[ "$code_backend" == "302" || "$code_backend" == "200" ]] || fail "Unexpected backend status: $code_backend"
  [[ "$code_login" == "200" ]] || fail "Unexpected login status: $code_login"

  log "Health OK (8001=$code_backend, 2083/login=$code_login)"
}

print_done() {
  cat <<EOF

Install complete.
Backup created at:
  $BACKUP_DIR

Rollback (if needed):
  cp -a "$BACKUP_DIR/users/database.py" "$PANEL_DIR/users/database.py"
  cp -a "$BACKUP_DIR/whm/views.py" "$PANEL_DIR/whm/views.py"
  cp -a "$BACKUP_DIR/whm/templates/whm/backup_restore.html" "$PANEL_DIR/whm/templates/whm/backup_restore.html"
  systemctl restart cp

EOF
}

main() {
  require_root
  check_paths
  backup_targets
  deploy_files
  run_checks
  restart_services
  health_checks
  print_done
}

main "$@"
