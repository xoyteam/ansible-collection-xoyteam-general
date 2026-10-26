# pgbasebackup_extdkr

Физический бэкап PostgreSQL через `pg_basebackup` в **короткоживущем контейнере
отдельного compose-проекта**. Контейнер запускается по cron, делает копию,
завершается и удаляется (`docker compose run --rm`); состояние контейнера не
сохраняется, копия пишется сразу в смонтированный каталог хоста.

Роль — альтернатива `pgbasebackup_dkr`: тот же результат и те же пути для
duplicity, но запуск описан декларативно через `docker compose` (образ, сеть,
том, `env_file`, пользователь), а не набором флагов `docker run`. Клиент
PostgreSQL на хосте не нужен.

## Отличия от `pgbasebackup_dkr`

| | `pgbasebackup_dkr` | `pgbasebackup_extdkr` |
|---|---|---|
| Запуск | `docker run --rm ...` из скрипта | `docker compose run --rm` отдельного проекта |
| Конфигурация | флаги в скрипте | `compose.yml` + `pgpass.env`, можно проверить `docker compose config` |
| Пароль | временный env-файл в `/tmp` | постоянный `pgpass.env` (`0600 root:root`), скрипт пароля не содержит |
| Блокировка | нет | `flock` на общем lock-файле |
| Метрики | `duplicity_backup` | `duplicity_backup` + timestamp + duration |
| Переменные | `pgdkr_*` | `pgextdkr_*` (см. таблицу соответствия) |

Обе роли — реализации одного и того же логического бэкапа: имя задания
`<bkp_name>_pgbasebackup`, каталоги `<data>/<job>`, `<bin>/<job>.sh`,
`<log>/<job>.log`. На одном хосте для одного `bkp_name` используйте **только одну**
из ролей `pgbasebackup_native` / `pgbasebackup_dkr` / `pgbasebackup_extdkr`.

## Требования

* Docker Engine и `docker compose` v2 (CLI), `flock` (util-linux);
* запущенный контейнер PostgreSQL (или внешняя БД и явная docker-сеть);
* пользователь PostgreSQL с правом `REPLICATION` (суперпользователь не обязателен);
* в `pg_hba.conf` разрешение на репликацию с адреса, с которого подключается
  бэкап-контейнер (см. «Сеть и pg_hba»);
* роль **не** устанавливает Docker и **не** правит `pg_hba.conf`/
  `postgresql.conf` — это ответственность роли, создающей кластер.

## Как это работает

Роль создаёт на задание отдельный compose-проект `pgbackup-<bkp_name>` в каталоге
`<duplicitybkp_path>/compose/<job>/`:

```
compose.yml     # сервис pgbackup, profiles: ["backup"], restart: "no"
pgpass.env      # PGPASSWORD=..., 0600 root:root
```

Сервис принадлежит профилю `backup`, поэтому `docker compose up -d` в этом
каталоге бэкап **не** запускает. Скрипт вызывает:

```bash
docker compose -f compose.yml -p pgbackup-<bkp_name> run --rm --no-deps --pull missing \
  pgbackup -D /backup -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" $PG_BASEBACKUP_OPTIONS
```

Образ и контейнер БД подставляются через переменные окружения compose
(`PGBACKUP_IMAGE`, `PGBACKUP_DB_CONTAINER`), которые экспортирует скрипт. Поэтому
`docker compose config` нужно запускать с этими переменными:

```bash
PGBACKUP_IMAGE=postgres:16 PGBACKUP_DB_CONTAINER=db \
  docker compose -f <compose_dir>/compose.yml config
```

Порядок работы скрипта:

1. проверки пути, наличия `docker`, `docker compose`, compose-файла и `flock`;
2. `flock -n` на lock-файле; занят — выход с кодом `75` без запуска контейнера;
3. определение контейнера БД и образа;
4. оценка размера `PGDATA` (`docker exec <db> du -sk`) и проверка свободного
   места с запасом `pgextdkr_space_margin_percent`; при нехватке текущая копия
   не удаляется;
5. удаление текущей копии, `mkdir` с `umask 077`;
6. `docker compose run --rm`; вывод команды построчно пишется в лог с отметкой
   времени;
7. при ошибке недописанная копия удаляется, код возврата `1`; при успехе —
   `0`, права `0700`, в лог пишется размер;
8. best-effort обновление textfile-метрик node_exporter.

## Переменные

| Переменная | По умолчанию | Обязательна | Описание |
|---|---|---|---|
| `bkp_name` | — | да | префикс задания; из него строятся job, проект и пути |
| `pgextdkr_pgpass` | `""` | да | пароль PostgreSQL; только из inventory/vault |
| `pgextdkr_pguser` | `postgres` | нет | пользователь с `REPLICATION` |
| `pgextdkr_pghost` / `pgextdkr_pgport` | `127.0.0.1` / `5432` | нет | адрес БД глазами бэкап-контейнера |
| `pgextdkr_db_container` | `""` | нет | имя контейнера БД; пусто — автоопределение |
| `pgextdkr_network` | `""` | нет | пусто — сеть контейнера БД; задано — внешняя docker-сеть |
| `postgres_version` | `""` | нет | major-версия для выбора образа (`"16"`, `"18"`) |
| `pgextdkr_image` | `""` | нет | явный образ; приоритет выше `postgres_version` |
| `pgextdkr_pgdata` | `/var/lib/postgresql/data` | нет | `PGDATA` в контейнере БД (оценка размера) |
| `pgextdkr_basebackup_options` | `-c fast` | нет | доп. опции `pg_basebackup` |
| `pgextdkr_container_user` | `0:0` | нет | пользователь бэкап-контейнера |
| `pgextdkr_compose_project` | `pgbackup-<bkp_name>` | нет | имя compose-проекта |
| `pgextdkr_compose_dir` | `<duplicitybkp_path>/compose/<job>` | нет | каталог compose-проекта |
| `pgextdkr_lock_file` | `/run/lock/pgbackup-<job>.lock` | нет | общий lock |
| `pgextdkr_space_margin_percent` | `20` | нет | запас места, % |
| `pgextdkr_min_free_kb` | `0` | нет | резервный минимум, если размер не оценён |
| `pgextdkr_pull_image` | `true` | нет | `docker pull` при установке, если образа нет |
| `pgextdkr_cron_minute` / `pgextdkr_cron_hour` | `03` / `0` | нет | расписание |
| `duplicitybkp_path` | `{{ backup_dir \| default('/home/backup') }}` | нет | корень `bin/data/log/compose` |
| `node_exporter_textfile_dir` | `""` | нет | каталог метрик; пусто — метрика не пишется |

Пути:

```
<duplicitybkp_path>/bin/<job>.sh
<duplicitybkp_path>/data/<job>
<duplicitybkp_path>/log/<job>.log
<duplicitybkp_path>/compose/<job>/compose.yml
<duplicitybkp_path>/compose/<job>/pgpass.env
```

### Соответствие переменным `pgbasebackup_dkr`

| `pgbasebackup_dkr` | `pgbasebackup_extdkr` |
|---|---|
| `pgdkr_pgpass` | `pgextdkr_pgpass` |
| `pgdkr_pguser` / `pgdkr_pghost` / `pgdkr_pgport` | `pgextdkr_pguser` / `pgextdkr_pghost` / `pgextdkr_pgport` |
| `pgdkr_db_container` | `pgextdkr_db_container` |
| `pgdkr_network` | `pgextdkr_network` |
| `pgdkr_image` | `pgextdkr_image` |
| `pgdkr_pgdata` | `pgextdkr_pgdata` |
| `pgdkr_basebackup_options` | `pgextdkr_basebackup_options` |
| `pgdkr_container_user` | `pgextdkr_container_user` |
| `pgdkr_space_margin_percent` | `pgextdkr_space_margin_percent` |
| `pgdkr_min_free_kb` | `pgextdkr_min_free_kb` |
| `pgdkr_cron_minute` / `pgdkr_cron_hour` | `pgextdkr_cron_minute` / `pgextdkr_cron_hour` |

`bkp_name`, `postgres_version`, `duplicitybkp_path`, `node_exporter_textfile_dir`
общие для всех pg-ролей.

## Сеть и pg_hba

Режим A (по умолчанию, `pgextdkr_network: ""`): бэкап-контейнер работает в
network namespace контейнера БД и подключается к `127.0.0.1:5432`. В `pg_hba.conf`:

```
host    replication     all     127.0.0.1/32    scram-sha-256
host    replication     all     ::1/128         scram-sha-256
```

Режим B (`pgextdkr_network: grafanadb`): бэкап-контейнер — отдельный контейнер,
который подключается через внешнюю docker-сеть (она должна существовать).
В `pg_hba.conf` нужна подсеть этой сети, например:

```
host    replication     all     172.19.0.0/24   scram-sha-256
```

В режиме B задайте `pgextdkr_pghost` на имя/адрес БД, доступный в этой сети, и не
оставляйте `127.0.0.1` (в своём netns он указывает на сам бэкап-контейнер).

При ошибке `pg_basebackup` вывод контейнера попадает в лог — там будет, например,
`no pg_hba.conf entry ...`. Роль конфигурацию PostgreSQL не меняет.

## Метрики

Если `node_exporter_textfile_dir` задан и каталог существует, роль создаёт его
(`0755 root:root`), а скрипт после успешного бэкапа best-effort пишет атомарно
файл `<job>.prom` (`0644`):

```
duplicity_backup{type="pg_basebackup_extdkr",project="<job>"} N
duplicity_backup_last_success_timestamp_seconds{type="pg_basebackup_extdkr",project="<job>"} <epoch>
duplicity_backup_duration_seconds{type="pg_basebackup_extdkr",project="<job>"} <sec>
```

`duplicity_backup` — счётчик запусков (циклически 1..9), совместимый по имени с
метрикой `pgbasebackup_dkr`/`pgbasebackup_native`; различайте задания по
`project`. Ошибка записи метрики не отменяет успешный бэкап и не меняет код
возврата. При неудачном бэкапе метрика не обновляется (ошибка видна по
устаревшему `last_success_timestamp_seconds`).

## Пример

```yaml
- name: PostgreSQL physical backup in compose
  hosts: dbservers
  become: true
  roles:
    - role: xoyteam.general.pgbasebackup_extdkr
      vars:
        bkp_name: pg01
        backup_dir: /var/backups/pg
        postgres_version: "16"
        pgextdkr_pghost: 127.0.0.1
        pgextdkr_pguser: postgres
        pgextdkr_pgpass: change-me
        node_exporter_textfile_dir: /var/lib/node_exporter/textfile
```

Для внешней сети:

```yaml
      vars:
        bkp_name: pg01
        postgres_version: "16"
        pgextdkr_network: backupnet
        pgextdkr_pghost: postgres
        pgextdkr_pguser: postgres
        pgextdkr_pgpass: change-me
```

Если запущен ровно один контейнер PostgreSQL, `pgextdkr_db_container` можно не
задавать; при нескольких — задайте явно или укажите `postgres_version`.

## Взаимодействие с duplicity

Роль держит **одну** локальную копию в `<data>/<job>` — её и забирает
`duplicitybkp` (ssh-режим забирает `duplicitybkp_data_path` целиком). Ретенции
локальных копий нет, историю хранит duplicity. Cron duplicity должен идти
**после** бэкапа; чтобы исключить пересечение, используйте в задании duplicity
тот же lock-файл (`pgextdkr_lock_file`, по умолчанию
`/run/lock/pgbackup-<job>.lock`) через `flock`.

## Восстановление (кратко)

1. Остановить целевой кластер.
2. Заменить содержимое `PGDATA` содержимым каталога копии (`<data>/<job>`).
3. Выставить владельца/права (`0700`, владелец пользователя PostgreSQL).
4. Запустить кластер и проверить `select 1`.

Копия снимается `pg_basebackup -c fast`, поэтому восстановление — штатное для
физической копии. Автоматизация restore в роль не входит.

## Ограничения

* одна локальная копия, без ретенции и ротации поколений;
* нет WAL-архивирования/PITR;
* нет таймаута и ретраев вокруг `docker compose run`;
* логический `pg_dump` — отдельная роль;
* `--pull missing` требует достаточно свежий `docker compose` (проверено на
  compose 2.36+); на старых версиях используйте `pgextdkr_pull_image` и
  предварительный `docker pull`.
