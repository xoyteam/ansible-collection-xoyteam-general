#!/bin/bash
# backup_metrics.sh — контракт метрик бэкапов v1.
#
# Подключается в генерируемые скрипты ролей duplicitybkp и pgbasebackup_*.
# Функции только определяют поведение; сами по себе ничего не запускают.
#
# Использование:
#   bm_init <project> <kind> <impl> <host> <route> <textfile_dir> [state_dir]
#   bm_phase_start <backup|upload|restore>
#   bm_phase_success <phase> [size_bytes] [duration_seconds]
#   bm_phase_fail <phase> [duration_seconds]
#
# Контракт и правила именования: docs/backup-metrics.md.

bm_now() { date +%s; }

bm_log() {
  printf '%s backup_metrics: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

bm_escape_label() {
  printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' '
}

bm_numeric() {
  case "${1:-}" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

bm_init() {
  BM_PROJECT="${1:-}"
  BM_KIND="${2:-}"
  BM_IMPL="${3:-}"
  BM_HOST="${4:-}"
  BM_ROUTE="${5:-dev}"
  BM_TEXTFILE_DIR="${6:-${node_exporter_textfile_dir:-}}"
  BM_STATE_DIR="${7:-/var/lib/backup-metrics}"
  BM_ENABLED=0
  BM_PHASE=""
  BM_START_EPOCH=0
  BM_DONE=0
  BM_STARTED=0
  BM_ATTEMPTS=0
  BM_FAILURES=0
  BM_LAST_SUCCESS=""
  BM_LAST_ATTEMPT=""
  BM_LAST_ATTEMPT_SUCCESS=""
  BM_LAST_DURATION=""
  BM_LAST_SIZE=""

  if [ -z "$BM_PROJECT" ] || [ -z "$BM_KIND" ] || [ -z "$BM_IMPL" ] || [ -z "$BM_HOST" ]; then
    bm_log "disabled: project/kind/impl/host must be set"
    return 0
  fi
  case "$BM_PROJECT" in
    *[!A-Za-z0-9_-]*)
      bm_log "disabled: project must match [A-Za-z0-9_-]: $BM_PROJECT"
      return 0 ;;
  esac
  if [ -z "$BM_TEXTFILE_DIR" ]; then
    bm_log "disabled: textfile dir is not set"
    return 0
  fi
  if ! mkdir -p -- "$BM_TEXTFILE_DIR" 2>/dev/null; then
    bm_log "disabled: cannot create textfile dir $BM_TEXTFILE_DIR"
    return 0
  fi
  if ! mkdir -p -- "$BM_STATE_DIR" 2>/dev/null; then
    bm_log "disabled: cannot create state dir $BM_STATE_DIR"
    return 0
  fi
  BM_ENABLED=1
}

bm_load_state() {
  [ -n "${BM_STATE_FILE:-}" ] && [ -f "$BM_STATE_FILE" ] || return 0
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      attempts)               BM_ATTEMPTS=$(bm_numeric "$value") ;;
      failures)               BM_FAILURES=$(bm_numeric "$value") ;;
      last_success)           [ -n "$value" ] && BM_LAST_SUCCESS="$value" || BM_LAST_SUCCESS="" ;;
      last_attempt)           [ -n "$value" ] && BM_LAST_ATTEMPT="$value" || BM_LAST_ATTEMPT="" ;;
      last_attempt_success)   [ -n "$value" ] && BM_LAST_ATTEMPT_SUCCESS=$(bm_numeric "$value") || BM_LAST_ATTEMPT_SUCCESS="" ;;
      last_duration)          [ -n "$value" ] && BM_LAST_DURATION="$value" || BM_LAST_DURATION="" ;;
      last_size)              [ -n "$value" ] && BM_LAST_SIZE="$value" || BM_LAST_SIZE="" ;;
    esac
  done < "$BM_STATE_FILE"
}

bm_save_state() {
  [ "$BM_ENABLED" = 1 ] || return 0
  local tmp="${BM_STATE_FILE}.$$"
  # umask только внутри subshell: не менять режим файлов, которые пишет скрипт.
  (
    umask 077
    {
      printf 'attempts=%s\n' "$BM_ATTEMPTS"
      printf 'failures=%s\n' "$BM_FAILURES"
      printf 'last_success=%s\n' "$BM_LAST_SUCCESS"
      printf 'last_attempt=%s\n' "$BM_LAST_ATTEMPT"
      printf 'last_attempt_success=%s\n' "$BM_LAST_ATTEMPT_SUCCESS"
      printf 'last_duration=%s\n' "$BM_LAST_DURATION"
      printf 'last_size=%s\n' "$BM_LAST_SIZE"
    } > "$tmp" && mv -f -- "$tmp" "$BM_STATE_FILE" && chmod 0600 -- "$BM_STATE_FILE"
  ) || {
    rm -f -- "$tmp"
    bm_log "cannot update state file $BM_STATE_FILE"
  }
  return 0
}

bm_write_prom() {
  [ "$BM_ENABLED" = 1 ] || return 0
  local labels tmp
  labels=$(printf 'project="%s",kind="%s",impl="%s",host="%s",phase="%s",backup_route="%s"' \
    "$(bm_escape_label "$BM_PROJECT")" \
    "$(bm_escape_label "$BM_KIND")" \
    "$(bm_escape_label "$BM_IMPL")" \
    "$(bm_escape_label "$BM_HOST")" \
    "$(bm_escape_label "$BM_PHASE")" \
    "$(bm_escape_label "$BM_ROUTE")")
  tmp=$(mktemp "${BM_TEXTFILE_DIR}/.backup_${BM_PROJECT}_${BM_PHASE}.XXXXXX") || {
    bm_log "cannot create temporary metric file in $BM_TEXTFILE_DIR"
    return 1
  }
  {
    printf '# HELP backup_last_attempt_timestamp_seconds Unix time of the last attempt\n'
    printf '# TYPE backup_last_attempt_timestamp_seconds gauge\n'
    printf 'backup_last_attempt_timestamp_seconds{%s} %s\n' "$labels" "$BM_LAST_ATTEMPT"
    printf '# HELP backup_last_attempt_success 1 if the last attempt succeeded, 0 otherwise\n'
    printf '# TYPE backup_last_attempt_success gauge\n'
    printf 'backup_last_attempt_success{%s} %s\n' "$labels" "$BM_LAST_ATTEMPT_SUCCESS"
    if [ -n "$BM_LAST_SUCCESS" ]; then
      printf '# HELP backup_last_success_timestamp_seconds Unix time of the last success\n'
      printf '# TYPE backup_last_success_timestamp_seconds gauge\n'
      printf 'backup_last_success_timestamp_seconds{%s} %s\n' "$labels" "$BM_LAST_SUCCESS"
    fi
    if [ -n "$BM_LAST_DURATION" ]; then
      printf '# HELP backup_duration_seconds Duration of the last attempt\n'
      printf '# TYPE backup_duration_seconds gauge\n'
      printf 'backup_duration_seconds{%s} %s\n' "$labels" "$BM_LAST_DURATION"
    fi
    if [ -n "$BM_LAST_SIZE" ]; then
      printf '# HELP backup_size_bytes Size of the last successful backup\n'
      printf '# TYPE backup_size_bytes gauge\n'
      printf 'backup_size_bytes{%s} %s\n' "$labels" "$BM_LAST_SIZE"
    fi
    printf '# HELP backup_attempts_total Total number of attempts\n'
    printf '# TYPE backup_attempts_total counter\n'
    printf 'backup_attempts_total{%s} %s\n' "$labels" "$BM_ATTEMPTS"
    printf '# HELP backup_failures_total Total number of failed attempts\n'
    printf '# TYPE backup_failures_total counter\n'
    printf 'backup_failures_total{%s} %s\n' "$labels" "$BM_FAILURES"
  } > "$tmp" || {
    rm -f -- "$tmp"
    bm_log "cannot write metric file $tmp"
    return 1
  }
  chmod 0644 -- "$tmp" && mv -f -- "$tmp" "${BM_PROM_FILE}"
}

bm_phase_start() {
  BM_PHASE="${1:-backup}"
  [ "$BM_ENABLED" = 1 ] || return 0
  BM_DONE=0
  BM_STARTED=1
  BM_START_EPOCH=$(bm_now)
  BM_STATE_FILE="${BM_STATE_DIR}/${BM_PROJECT}_${BM_PHASE}.state"
  BM_PROM_FILE="${BM_TEXTFILE_DIR}/backup_${BM_PROJECT}_${BM_PHASE}.prom"
  bm_load_state
  BM_ATTEMPTS=$(( BM_ATTEMPTS + 1 ))
  bm_save_state
}

bm_phase_success() {
  local phase="${1:-${BM_PHASE:-backup}}"
  [ "$BM_ENABLED" = 1 ] || return 0
  [ "${BM_STARTED:-0}" = 1 ] || return 0
  [ "$BM_DONE" = 1 ] && return 0
  BM_PHASE="$phase"
  [ -n "${BM_STATE_FILE:-}" ] || BM_STATE_FILE="${BM_STATE_DIR}/${BM_PROJECT}_${BM_PHASE}.state"
  [ -n "${BM_PROM_FILE:-}" ] || BM_PROM_FILE="${BM_TEXTFILE_DIR}/backup_${BM_PROJECT}_${BM_PHASE}.prom"
  local size="${2:-}" duration="${3:-}"
  [ -n "$duration" ] || duration=$(( $(bm_now) - BM_START_EPOCH ))
  BM_LAST_SUCCESS=$(bm_now)
  BM_LAST_ATTEMPT="$BM_LAST_SUCCESS"
  BM_LAST_ATTEMPT_SUCCESS=1
  BM_LAST_DURATION="$duration"
  [ -n "$size" ] && BM_LAST_SIZE="$size"
  BM_DONE=1
  bm_save_state
  bm_write_prom || bm_log "failed to update metric for ${BM_PROJECT}/${BM_PHASE}"
}

bm_phase_fail() {
  local phase="${1:-${BM_PHASE:-backup}}"
  [ "$BM_ENABLED" = 1 ] || return 0
  [ "${BM_STARTED:-0}" = 1 ] || return 0
  [ "$BM_DONE" = 1 ] && return 0
  BM_PHASE="$phase"
  [ -n "${BM_STATE_FILE:-}" ] || BM_STATE_FILE="${BM_STATE_DIR}/${BM_PROJECT}_${BM_PHASE}.state"
  [ -n "${BM_PROM_FILE:-}" ] || BM_PROM_FILE="${BM_TEXTFILE_DIR}/backup_${BM_PROJECT}_${BM_PHASE}.prom"
  local duration="${2:-}"
  [ -n "$duration" ] || duration=$(( $(bm_now) - BM_START_EPOCH ))
  BM_LAST_ATTEMPT=$(bm_now)
  BM_LAST_ATTEMPT_SUCCESS=0
  BM_LAST_DURATION="$duration"
  BM_FAILURES=$(( BM_FAILURES + 1 ))
  BM_DONE=1
  bm_save_state
  bm_write_prom || bm_log "failed to update metric for ${BM_PROJECT}/${BM_PHASE}"
}
