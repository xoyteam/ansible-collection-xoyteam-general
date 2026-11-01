# Соглашение об именах и метриках бэкапов

Единый контракт для ролей `duplicitybkp`, `pgbasebackup_native`,
`pgbasebackup_dkr` и `pgbasebackup_extdkr`. Нужен, чтобы мониторинг
(алерты, дашборды, реестр бэкапов в потребляющем проекте) не заводил
отдельные правила на каждый бэкап, а работал по общим шаблонам.

Статус: **контракт v1 внедрён в роли** (`duplicitybkp`, `pgbasebackup_*`).
Старые метрики `duplicity_*` удалены 2026-11-01; остался только `backup_*`.
совместимости; новые роли и правки должны писать только `backup_*`.

---

## 1. Принципы

* Идентичность бэкапа — набор labels, а не имя правила/панели.
* Одна роль может обслуживать много заданий; задание задаётся `project`.
* Имя метрики отвечает на вопрос «что измеряем», labels — «для какого
  задания и фазы».
* Все значения времени — Unix epoch в секундах; длительности — секунды;
  размеры — байты.
* Метрики пишутся в textfile-коллектор `node_exporter` атомарно.
* Секретов, паролей, строк подключения и путей с секретами в labels нет.

---

## 2. Labels

| Label | Обязателен | Значения | Смысл |
|---|---|---|---|
| `project` | да | `^[a-z][a-z0-9_]{1,31}$` | Стабильный ID задания. Не меняется при смене реализации, хоста или хранилища. Уникален в пределах парка. |
| `kind` | да | `mysql`, `postgres`, `files`, … | Класс данных. Не реализация и не имя роли. |
| `impl` | да | `duplicitybkp_ssh`, `mysqlbkp_fullcfg`, `pgbasebackup_native`, `pg_basebackup_extdkr`, … | Реализация, которая пишет метрику. Нужна для отладки. |
| `phase` | да | `backup`, `upload`, `restore` | Этап. `backup` — создание копии, `upload` — отправка в хранилище, `restore` — проверка восстановления. |
| `host` | да | имя хоста из inventory | Канонический хост, а не IP и не адрес скрейпа. |
| `backup_route` | да | `dev`, `prod` | Куда маршрутизировать алерты по этому заданию. |
| `store` | для реестра | id хранилища | Например, `backup-store`, `s3`. Не URL. |
| `enabled` | только реестр | `true`, `false` | Отключённое задание видно в таблице, но не алертит. |
| `owner` | только реестр | короткий id | Ответственный за задание. |
| `schedule` | только реестр | cron-строка | Расписание создания копии. |
| `schedule_class` | только реестр | `daily`, `weekly` | Класс расписания для порогов по умолчанию. |

Запрещено использовать labels `job` и `instance`: их добавляет сам Prometheus,
экспортированные значения превратятся в `exported_job`/`exported_instance` или
перезапишут target labels.

---

## 3. Метрики на хосте бэкапа

Пишутся в каталог textfile-коллектора, по одному файлу на
`project` + `phase`:

```text
backup_<project>_<phase>.prom
```

| Метрика | Тип | Когда пишется | Смысл |
|---|---|---|---|
| `backup_last_attempt_timestamp_seconds` | gauge | каждая попытка | Время начала/окончания последней попытки. |
| `backup_last_attempt_success` | gauge 0/1 | каждая попытка | `1` — успех, `0` — ошибка. |
| `backup_last_success_timestamp_seconds` | gauge | только успех | Время последнего успеха. До первого успеха серии нет. |
| `backup_duration_seconds` | gauge | успех | Длительность последней успешной попытки. |
| `backup_size_bytes` | gauge | успех, best-effort | Размер копии. Если посчитать нельзя — серия не пишется. |
| `backup_attempts_total` | counter | каждая попытка | Всего попыток. |
| `backup_failures_total` | counter | ошибка | Всего ошибок. |

Правила:

* при ошибке `last_success` не обновляется, `last_attempt_success=0`;
* ошибка записи метрики не должна отменять уже успешный бэкап;
* state-файл (`0600`) хранит счётчики и последний успех между запусками;
* общий helper — `roles/backup_metrics/files/backup_metrics.sh`; он
  встраивается в генерируемый скрипт, а не устанавливается отдельной ролью;
* `.prom` — `0644`, запись через временный файл + `mv`;
* не писать две разные метрики с одинаковым набором labels в разные файлы.

Пример:

```prometheus
backup_last_attempt_timestamp_seconds{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 1767000180
backup_last_attempt_success{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 1
backup_last_success_timestamp_seconds{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 1767000180
backup_duration_seconds{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 42
backup_size_bytes{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 734003200
backup_attempts_total{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 37
backup_failures_total{project="pg01",kind="postgres",impl="pg_basebackup_extdkr",host="db01",phase="backup",backup_route="dev"} 0
```

---

## 4. Метрики реестра (центральные)

Генерируются потребляющим проектом из реестра бэкапов, а не скриптом бэкапа:

| Метрика | Labels | Смысл |
|---|---|---|
| `backup_registry_info` | `project, kind, impl, host, store, schedule, schedule_class, enabled, owner, backup_route` | Настройки задания; `1` для каждого задания, включая `enabled=false`. |
| `backup_registry_max_age_seconds` | `project, kind, phase, backup_route` | Порог свежести для фазы. |
| `backup_job_expected` | те же, что у `backup_registry_info`, + `phase` | Задание включено и должно работать; используется для алерта «никогда не было успеха». |

Порог — значение в метрике, а не отдельное правило: одно общее правило
сравнивает `time() - backup_last_success_timestamp_seconds` с
`backup_registry_max_age_seconds` через `on(project, kind, phase)`.

---

## 5. Соглашение об именах

### `project`

* только `a-z`, цифры и `_`, начинается с буквы;
* отражает данные/задание, а не хост: `pg01`, `labdb`, `monpg`;
* не содержит тип реализации (`_extdkr`, `_native`) — для этого есть `impl`;
* не меняется при переезде задания на другой хост или в другую роль;
* уникален в пределах всего парка.

### `kind`

Класс данных, а не технология:

| Данные | `kind` |
|---|---|
| MySQL/MariaDB | `mysql` |
| PostgreSQL | `postgres` |
| Файлы/каталоги | `files` |
| Redis | `redis` |

Новую реализацию того же класса добавляйте как новый `impl`, а не новый `kind`.

### `impl`

Имя роли или режима, который пишет метрику. Для `duplicitybkp` это `bkptype`
(`duplicitybkp_ssh`, `mysqlbkp_fullcfg`), для PostgreSQL — имя роли
(`pgbasebackup_native`, `pg_basebackup_extdkr`).

### `phase`

* `backup` — локальная копия создана;
* `upload` — копия отправлена в хранилище;
* `restore` — проверено восстановление (пока не внедрено).

Одно задание может иметь несколько фаз; каждая фаза пишет свой файл и свой
порог.

---

## 6. Маршрутизация алертов

`backup_route` — часть контракта, а не только настройка Grafana:

* значение задаётся в реестре для каждого задания;
* попадает в labels метрик;
* правила, которые читают новые `backup_*`-метрики, **не должны** задавать
  статический label `backup_route` — иначе он перекроет значение из серии;
* legacy-правила удалены; статический `backup_route` для них больше не нужен;
* `dev` — отладочный получатель, `prod` — рабочий.

---

## 7. Обратная совместимость

На время перехода роли могут писать и старые метрики:

| Старая | Новая |
|---|---|
| `duplicity_backup{type,project}` | `backup_last_success_timestamp_seconds{project,kind,impl,host,phase,backup_route}` + счётчики |
| `duplicity_upload{type,project}` | то же с `phase="upload"` |
| `duplicity_backup_last_success_timestamp_seconds` | `backup_last_success_timestamp_seconds` |

Старые метрики удаляются после того, как все правила и дашборды переведены на
`backup_*` (не раньше одного релиза/периода наблюдения).

---

## 8. Чек-лист для новой роли/режима бэкапа

1. Выберите `project` по правилам выше; проверьте уникальность в реестре.
2. Определите `kind` (класс данных) и `impl` (имя роли/режима).
3. Для каждой фазы (`backup`, `upload`, …) пишите свой `.prom`-файл.
4. Пишите `last_attempt_*` всегда, `last_success` — только при успехе.
5. Добавьте `backup_route` из переменной роли/реестра.
6. Не используйте labels `job` и `instance`.
7. Зарегистрируйте задание в реестре потребляющего проекта.
8. Проверьте: успех, падение, устаревание, отсутствие первой метрики.
9. Обновите README роли и это соглашение, если появились новые labels/метрики.

---

## 9. Связанные документы

* [README коллекции](../README.md)
* [duplicitybkp](../roles/duplicitybkp/README.md)
* [pgbasebackup_native](../roles/pgbasebackup_native/README.md)
* [pgbasebackup_dkr](../roles/pgbasebackup_dkr/README.md)
* [pgbasebackup_extdkr](../roles/pgbasebackup_extdkr/README.md)
