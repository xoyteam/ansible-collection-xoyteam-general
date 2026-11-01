# backup_metrics

Не отдельная исполняемая роль, а общий shell-helper для ролей бэкапов:
`files/backup_metrics.sh`.

Он встраивается в генерируемые скрипты через
`lookup('file', role_path ~ '/../backup_metrics/files/backup_metrics.sh')`,
поэтому установленной копии на хосте не требуется.

API:

```bash
bm_init <project> <kind> <impl> <host> <route> <textfile_dir> [state_dir]
bm_phase_start <backup|upload|restore>
bm_phase_success <phase> [size_bytes] [duration_seconds]
bm_phase_fail <phase> [duration_seconds]
```

Пишет `backup_last_attempt_timestamp_seconds`, `backup_last_attempt_success`,
`backup_last_success_timestamp_seconds`, `backup_duration_seconds`,
`backup_size_bytes`, `backup_attempts_total`, `backup_failures_total` в
textfile-коллектор `node_exporter`, атомарно и best-effort. Ошибка метрик не
отменяет бэкап.

Контракт и правила именования — [docs/backup-metrics.md](../../docs/backup-metrics.md).
