# pg_docker_swarm

PostgreSQL в Docker Swarm: отдельный стек и отдельная attachable overlay-сеть.
Другие стеки (например, Bareos) подключаются к этой сети как к `external`,
поэтому по умолчанию БД не публикует порт наружу и доступна только по имени
сервиса `postgres` внутри overlay.

Если нужен доступ с хоста/извне (lab2, `mysql84`-подобная схема), задайте
`pgdocker_swarm_publish_port` — роль опубликует порт через Swarm ingress и
проверит, что он действительно опубликован.

Хост должен быть в Swarm (`docker swarm init`); роль этого не делает.

## Переменные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `pgdocker_swarm_stack` | `pg` | имя стека (`docker stack deploy ... <stack>`) |
| `pgdocker_swarm_service` | `postgres` | имя сервиса; контейнер `<stack>_<service>.1.*` |
| `pgdocker_swarm_image` | `postgres:17` | образ |
| `pgdocker_swarm_install_path` | `/home/docker/<stack>` | каталог стека |
| `pgdocker_swarm_data_dir` | `<install_path>/data` | bind-mount данных (uid/gid 999) |
| `pgdocker_swarm_network` | `<stack>-net` | имя attachable overlay-сети |
| `pgdocker_swarm_db` | `postgres` | `POSTGRES_DB` |
| `pgdocker_swarm_user` | `postgres` | `POSTGRES_USER` |
| `pgdocker_swarm_password` | `change-me` | `POSTGRES_PASSWORD` (обязательно переопределить) |
| `pgdocker_swarm_pgdata` | `/var/lib/postgresql/data` | `PGDATA` и target bind-mount |
| `pgdocker_swarm_publish_port` | `null` | published-порт на хост; `null`/`0` — не публиковать |
| `pgdocker_swarm_publish_mode` | `ingress` | режим публикации Swarm |
| `pgdocker_swarm_initdb_args` | `""` | необязательные `POSTGRES_INITDB_ARGS` |
| `pgdocker_swarm_timezone` | `""` | необязательный `TZ` контейнера |
| `pgdocker_swarm_uid` / `gid` | `999` | владелец data-dir |
| `pgdocker_swarm_replicas` | `1` | реплики сервиса |
| `pgdocker_swarm_env` | `{}` | доп. env-переменные |

## Что делает

1. Проверяет вход и что Swarm активен (иначе — понятная ошибка).
2. Создаёт каталог стека и `data/` с uid/gid 999.
3. Создаёт attachable overlay-сеть (`docker network create -d overlay --attachable`).
4. Рендерит `stack.yml` (0600 — в нём пароль).
5. `docker stack deploy --with-registry-auth`.
6. Ждёт, пока сервис выйдет в `1/1`.
7. Если задан `pgdocker_swarm_publish_port` — проверяет, что порт есть
   в `.Endpoint.Ports` сервиса.

`PGDATA` задаётся явно: в `postgres:18` дефолт —
`/var/lib/postgresql/18/docker`, и без явного `PGDATA` bind-mount
`/var/lib/postgresql/data` остался бы пустым. Для `postgres:17` значение
совпадает с дефолтом.

## Пример без публикации порта (Bareos)

```yaml
- hosts: backup_coordinator
  become: true
  roles:
    - role: xoyteam.general.pg_docker_swarm
      vars:
        pgdocker_swarm_stack: bareos-pg
        pgdocker_swarm_network: bareos-pg-net
        pgdocker_swarm_db: bareos
        pgdocker_swarm_user: bareos
        pgdocker_swarm_password: "{{ bareos_catalog_password }}"
```

Потребитель (стек Bareos) подключает сеть так:

```yaml
networks:
  pgnet:
    external: true
    name: bareos-pg-net
```

и обращается к БД по хосту `postgres` (имя сервиса).

## Пример с публикацией порта (lab2)

```yaml
- hosts: gemohelp.lab2
  become: true
  roles:
    - role: xoyteam.general.pg_docker_swarm
      vars:
        pgdocker_swarm_stack: postgres
        pgdocker_swarm_image: "postgres:18.6"
        pgdocker_swarm_install_path: /home/dkradm/app/postgres
        pgdocker_swarm_network: dbnet
        pgdocker_swarm_db: mydb
        pgdocker_swarm_user: postgres
        pgdocker_swarm_password: "{{ lab2_pg_password }}"
        pgdocker_swarm_pgdata: /var/lib/postgresql/data
        pgdocker_swarm_initdb_args: "--data-checksums"
        pgdocker_swarm_timezone: Europe/Moscow
        pgdocker_swarm_publish_port: 5432
```

Порт публикуется на всех интерфейсах хоста (`*:5432->5432/tcp`), как
`mysql84` на `*:3307->3306/tcp`. Доступ — по паролю (`pg_hba` официального
образа разрешает `host all all all scram-sha-256`).
