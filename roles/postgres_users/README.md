# postgres_users

Создаёт в PostgreSQL три роли и прикладную базу:

| Роль | Имя по умолчанию | Права |
|---|---|---|
| прикладная | `postgres_users_service` | `LOGIN`, владелец одноимённой базы |
| репликация | `replicator` | `LOGIN`, `REPLICATION` |
| мониторинг | `observer` | `LOGIN`, членство в `pg_monitor` |

Имя прикладного пользователя и имя базы **совпадают** с именем сервиса:
`postgres_users_service` задаётся в плейбуке. Если база уже существует
(например, создана `POSTGRES_DB` в `pg_docker_swarm`), роль меняет её
владельца на прикладного пользователя.

## Секреты

Пароли генерируются `lookup('password')`: длина 32, только буквы и цифры
(`ascii_letters,digits`), без спецсимволов. Файлы:

```
credentials-crypt/<inventory_hostname>/<service>_<dbms>_svc
credentials-crypt/<inventory_hostname>/replicator_<dbms>_replication
credentials-crypt/<inventory_hostname>/observer_<dbms>_monitoring
```

`<dbms>` — `postgres_users_dbms_name` (по умолчанию `postgres`).
`credentials-crypt/` в потребляющем проекте должен быть под git-crypt.
Пароли не выводятся: задачи с ними помечены `no_log`.

## Переменные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `postgres_users_service` | — | имя сервиса; оно же имя прикладного пользователя и БД |
| `postgres_users_admin_host` | `127.0.0.1` | хост PostgreSQL для администратора |
| `postgres_users_admin_port` | `5432` | порт |
| `postgres_users_admin_user` | `postgres` | суперпользователь |
| `postgres_users_admin_password` | — | его пароль (обязателен) |
| `postgres_users_admin_db` | `postgres` | maintenance DB |
| `postgres_users_dbms_name` | `postgres` | часть имени секрета |
| `postgres_users_replication_user` | `replicator` | имя роли репликации |
| `postgres_users_monitoring_user` | `observer` | имя роли мониторинга |
| `postgres_users_monitoring_group` | `pg_monitor` | группа прав мониторинга |
| `postgres_users_credentials_dir` | `credentials-crypt/<host>` | каталог секретов |
| `postgres_users_password_length` | `32` | длина пароля (>= 20) |
| `postgres_users_app_password` | lookup | можно переопределить |
| `postgres_users_replication_password` | lookup | можно переопределить |
| `postgres_users_monitoring_password` | lookup | можно переопределить |

## Пример

```yaml
- hosts: gemohelp.lab2
  become: true
  roles:
    - role: xoyteam.general.pg_docker_swarm
      vars:
        pgdocker_swarm_publish_port: 5432
        # ...
    - role: xoyteam.general.postgres_users
      vars:
        postgres_users_service: mydb
        postgres_users_admin_password: "{{ pgdocker_swarm_password }}"
```

Роль работает по TCP; PostgreSQL должен быть доступен с хоста, на котором
запускается Ansible (для `pg_docker_swarm` — published-порт или иной
доступный endpoint). На хосте нужен `python3-psycopg2`; роль ставит его
через apt.

## Ограничения

- Для репликации роль создаёт пользователя `replicator` с `REPLICATION`, но
  **не правит `pg_hba.conf`**. Для подключения реплики нужна строка
  `host replication replicator <сеть> scram-sha-256` (или аналог).
- Роль не создаёт слоты репликации, публикации и не настраивает `pg_basebackup`.
- `pg_monitor` — предопределённая роль PostgreSQL 10+; для старых версий
  членство нужно заменить.
- Смена пароля в lookup-файле обновляет пароль роли при следующем прогоне
  (`postgresql_user`); `ALTER ROLE` вручную не требуется.
