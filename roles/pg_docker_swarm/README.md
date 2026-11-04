# pg_docker_swarm

PostgreSQL в Docker Swarm: отдельный стек и отдельная attachable overlay-сеть.
Другие стеки (например, Bareos) подключаются к этой сети как к `external`,
поэтому БД не публикует порт наружу и доступна только по имени сервиса
`postgres` внутри overlay.

Хост должен быть в Swarm (`docker swarm init`); роль этого не делает.

## Переменные

| Переменная | По умолчанию | Описание |
|---|---|---|
| `pgdocker_swarm_stack` | `pg` | имя стека (`docker stack deploy ... <stack>`) |
| `pgdocker_swarm_image` | `postgres:17` | образ |
| `pgdocker_swarm_install_path` | `/home/docker/<stack>` | каталог стека |
| `pgdocker_swarm_data_dir` | `<install_path>/data` | bind-mount данных (uid/gid 999) |
| `pgdocker_swarm_network` | `<stack>-net` | имя attachable overlay-сети |
| `pgdocker_swarm_db` | `postgres` | `POSTGRES_DB` |
| `pgdocker_swarm_user` | `postgres` | `POSTGRES_USER` |
| `pgdocker_swarm_password` | `change-me` | `POSTGRES_PASSWORD` (обязательно переопределить) |
| `pgdocker_swarm_uid` / `gid` | `999` | владелец data-dir |
| `pgdocker_swarm_replicas` | `1` | реплики сервиса |
| `pgdocker_swarm_env` | `{}` | доп. env-переменные |

## Что делает

1. Проверяет, что Swarm активен (иначе — понятная ошибка).
2. Создаёт каталог стека и `data/` с uid/gid 999.
3. Создаёт attachable overlay-сеть (`docker network create -d overlay --attachable`).
4. Рендерит `stack.yml` (0600 — в нём пароль).
5. `docker stack deploy --with-registry-auth`.
6. Ждёт, пока сервис выйдет в `1/1`.

## Пример

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
