#!/usr/bin/env bash
set -euo pipefail

PANEL_DIR="${PANEL_DIR:-/usr/local/olspanel/mypanel}"
BACKUP_ROOT="${BACKUP_ROOT:-/root/hsetiacptoolspanel-backups}"
UNINSTALL_BACKUP_ROOT="${UNINSTALL_BACKUP_ROOT:-/root/hsetiacptoolspanel-uninstall-backups}"
TS="$(date +%Y%m%d_%H%M%S)"
UNINSTALL_BACKUP_DIR="$UNINSTALL_BACKUP_ROOT/$TS"

REQUIRED_FILES=(
  "users/database.py"
  "whm/views.py"
  "whm/templates/whm/backup_restore.html"
)

SELECTED_BACKUP_DIR=""
LIST_ONLY="0"

log() {
  printf '[hestia-olspanel] %s\n' "$*"
}

fail() {
  printf '[hestia-olspanel] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: ./uninstall.sh [--backup-dir <path>] [--latest] [--list]

Options:
  --backup-dir <path>  Restore from a specific install backup directory.
  --latest             Restore from the latest directory in $BACKUP_ROOT.
  --list               List available backup directories and exit.

Default behavior:
  If no option is provided, --latest is used.
EOF
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    fail "Run as root."
  fi
}

list_backups() {
  [[ -d "$BACKUP_ROOT" ]] || {
    log "No backup root found: $BACKUP_ROOT"
    return 0
  }

  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort
}

resolve_latest_backup() {
  local latest
  latest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)"
  [[ -n "$latest" ]] || fail "No backup directories found in $BACKUP_ROOT"
  SELECTED_BACKUP_DIR="$latest"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backup-dir)
        shift
        [[ $# -gt 0 ]] || fail "--backup-dir requires a path"
        SELECTED_BACKUP_DIR="$1"
        ;;
      --latest)
        SELECTED_BACKUP_DIR=""
        ;;
      --list)
        LIST_ONLY="1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
    shift
  done
}

validate_paths() {
  [[ -d "$PANEL_DIR" ]] || fail "OLSPanel path not found: $PANEL_DIR"

  if [[ -z "$SELECTED_BACKUP_DIR" ]]; then
    resolve_latest_backup
  fi

  [[ -d "$SELECTED_BACKUP_DIR" ]] || fail "Backup directory not found: $SELECTED_BACKUP_DIR"

  for rel in "${REQUIRED_FILES[@]}"; do
    [[ -f "$SELECTED_BACKUP_DIR/$rel" ]] || fail "Backup file missing: $SELECTED_BACKUP_DIR/$rel"
    [[ -f "$PANEL_DIR/$rel" ]] || fail "Target file missing: $PANEL_DIR/$rel"
  done
}

backup_current_before_restore() {
  mkdir -p "$UNINSTALL_BACKUP_DIR"
  log "Saving current files before uninstall: $UNINSTALL_BACKUP_DIR"

  for rel in "${REQUIRED_FILES[@]}"; do
    mkdir -p "$UNINSTALL_BACKUP_DIR/$(dirname "$rel")"
    cp -a "$PANEL_DIR/$rel" "$UNINSTALL_BACKUP_DIR/$rel"
  done
}

restore_backup_files() {
  log "Restoring files from: $SELECTED_BACKUP_DIR"

  for rel in "${REQUIRED_FILES[@]}"; do
    install -D -m 0644 "$SELECTED_BACKUP_DIR/$rel" "$PANEL_DIR/$rel"
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

restart_and_check() {
  log "Restarting services"
  systemctl restart cp
  systemctl is-active --quiet cp || fail "cp service is not active after restart"

  systemctl restart lsws 2>/dev/null || systemctl restart openlitespeed 2>/dev/null || true

  local code_backend
  local code_login
  code_backend="$(curl -k -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8001/ || true)"
  code_login="$(curl -k -s -o /dev/null -w '%{http_code}' https://127.0.0.1:2083/login/ || true)"

  [[ "$code_backend" == "302" || "$code_backend" == "200" ]] || fail "Unexpected backend status: $code_backend"
  [[ "$code_login" == "200" ]] || fail "Unexpected login status: $code_login"

  log "Health OK (8001=$code_backend, 2083/login=$code_login)"
}

print_done() {
  cat <<EOF

Uninstall complete.
Restored from:
  $SELECTED_BACKUP_DIR

Current files before uninstall were saved at:
  $UNINSTALL_BACKUP_DIR

Re-apply addon quickly:
  cd /root/hsetiacptoolspanel
  ./install.sh

EOF
}

main() {
  require_root
  parse_args "$@"

  if [[ "$LIST_ONLY" == "1" ]]; then
    list_backups
    exit 0
  fi

  validate_paths
  backup_current_before_restore
  restore_backup_files
  run_checks
  restart_and_check
  print_done
}

main "$@"
