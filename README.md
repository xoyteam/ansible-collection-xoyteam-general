# xoyteam.general

Ансабл-коллекция общих ролей `xoyteam`: резервное копирование (duplicity,
`mysqldump`, физический бэкап PostgreSQL) и запуск инфраструктурных сервисов в
`docker compose` (Prometheus, exporters, MySQL, DNS-прокси, Immich, acme.sh).

Коллекция не является control-node: inventory, `group_vars`/`host_vars` и реальные
реквизиты живут в потребляющем проекте и передаются в роли переменными.

> **Репозиторий публичный.** Паролей, токенов, ключей, IP и реальных имён хостов в
> нём быть не должно. Пароль MySQL роль `duplicitybkp` читает из
> `credentials-crypt/<host>/mysql_bkp_password` рядом с playbook потребляющего
> проекта (git-crypt); в примерах ниже — только заглушки вида `change-me`.

Версия коллекции: `2.0.0` (тегов нет). CI и тестов в репозитории нет.

---

## Состав коллекции

| Роль | Назначение | Состояние |
|------|------------|-----------|
| `duplicitybkp` | Диспетчер бэкапов: duplicity в Swift/S3/SSH, `mysqldump` по расписанию, скрипты, cron, logrotate | Рабочая; режим задаётся `bkptype` |
| `pgbasebackup_native` | Физический бэкап PostgreSQL через `pg_basebackup` на хосте + cron, logrotate, метрика | Рабочая |
| `pgbasebackup_dkr` | То же, но `pg_basebackup` выполняется в Docker-контейнере; клиент PostgreSQL на хосте не нужен | Рабочая |
| `install_duplicity` | Заготовка установки duplicity | Пустая, не используется (установка в `duplicitybkp`) |
| `pg_docker` | PostgreSQL в `docker compose` | Заготовка, handler использует устаревший `docker_compose` v1 |
| `mysql_server` | MySQL в `docker compose` | Заготовка |
| `postgres_exporter` | `postgres_exporter` в `docker compose` | Заготовка |
| `prometheus` | Prometheus в `docker compose` | Заготовка |
| `prometheus_node_exporter` | `node_exporter` в `docker compose` | Заготовка |
| `dns_proxy` | DNS-прокси (mageddo/dns-proxy-server) в `docker compose` | Заготовка |
| `immich_docker` | Развёртывание Immich из официального `docker-compose.yml` | Заготовка |
| `acme_sh` | Установка `acme.sh` и выпуск сертификатов Let's Encrypt через DNS-01 (Selectel) | Рабочая |

Роль `dkr_pgbackup` удалена в версии `2.0.0`: её заменила `pgbasebackup_dkr`.
Обе `pgbasebackup_*` и патч `duplicitybkp` синхронизированы с коллекцией
`xoyteam.duplicitybkp` (коммиты `556d060`, `718c617`, `ea4db5d`).

---

## Бэкапы

### `duplicitybkp`

Одна роль-диспетчер, всё поведение определяется переменной `bkptype`:
`duplicity`, `ssh_key`, `duplicitybkp_ssh`, `swift`, `swift_fullcfg`,
`duplicitybkp_s3`, `mysql`, `mysql_fullcfg`, `mysqlclient`,
`mysqlclient_fullcfg`. Для файловых режимов роль ставит duplicity, создаёт скрипт,
cron и logrotate; для MySQL — скрипт `mysqldump` и конфиг со списком баз.

Пароль MySQL не генерируется ролью и не хранится в ней: по умолчанию он читается
на control-node из `{{ playbook_dir }}/credentials-crypt/<mysqlbkp_host>/mysql_bkp_password`
(файл должен быть расшифрован `git-crypt unlock`). Пустой или отсутствующий файл —
ошибка. Явно заданный `mysqlbkp_pass` имеет приоритет.

Каталоги, которыми управляет роль, — `0750 root:<mysqlbkp_dir_group>` (по умолчанию
`adm`), конфиги/дампы/логи — `0600 root:root`, скрипты — `0700 root:root`. Подробности
и полный список переменных — в [README роли](roles/duplicitybkp/README.md).

### `pgbasebackup_native` и `pgbasebackup_dkr`

Физический бэкап PostgreSQL с проверкой свободного места, удалением предыдущей
локальной копии, корректными кодами возврата и best-effort метрикой для
`node_exporter`. `pgbasebackup_native` использует `pg_basebackup` с хоста,
`pgbasebackup_dkr` — образ PostgreSQL в Docker (автоопределение контейнера БД,
образ из контейнера или `postgres:<postgres_version>`, `PGPASSWORD` через
`--env-file`, а не в аргументах). Локальная копия одна: её должен забрать duplicity
до следующего запуска. Переменные и примеры — в README ролей.

---

## Требования и использование

| Зависимость | Зачем |
|-------------|-------|
| `community.crypto`, `ansible.posix` | `ssh_key` в `duplicitybkp` |
| `community.docker` | Docker-роли (`pg_docker`, `pgbasebackup_dkr` и др.) |
| `community.docker` `docker compose` v2 | Все compose-роли |

```yaml
- name: PostgreSQL physical backup
  hosts: dbservers
  become: true
  roles:
    - role: xoyteam.general.pgbasebackup_dkr
      vars:
        bkp_name: pg01
        backup_dir: /var/backups/pg
        postgres_version: "16"
        pgdkr_pgpass: change-me
        node_exporter_textfile_dir: /var/lib/node_exporter/textfile
```

Полноценный прогон — только по явной команде и с `--limit <host>`: роли создают
cron-задания и перезаписывают конфиги. Для проверки достаточно
`ansible-playbook --syntax-check`.

`requirements.yml` в репозитории устарел (ссылается на старые роли и Bitbucket);
перед использованием обновите его под свой проект.

---

## Лицензия

GPL-3.0-or-later. См. [LICENSE](LICENSE).
