duplicitybkp
=========

Backup for duplicity

Requirements
------------

Ansible 2.14+. Для ssh-режима на control-node нужен `ssh-keyscan`
(пакет `openssh-client`), на целевом хосте — `ssh-keygen` (его требует модуль
`ansible.builtin.known_hosts`; входит в тот же пакет `openssh-client`), для
`mysql` — `mysqldump` на целевом хосте.

Role Variables
--------------

Полный список — в `defaults/main.yml`. Переменные доступа к хранилищу в
defaults намеренно не заданы: их передаёт потребляющий проект.

Обязательные для `bkptype: duplicitybkp_ssh`:

| Переменная | Назначение |
|---|---|
| `duplicitybkp_ssh_store_user` | пользователь на хосте-хранилище |
| `duplicitybkp_ssh_store_host` | хост/IP хранилища (в примерах — `backup.example`) |
| `duplicitybkp_ssh_store_path` | каталог на хранилище (по умолчанию — имя задания) |
| `duplicitybkp_ssh_store_hostname` | хост для `delegate_to` (по умолчанию = `store_host`) |
| `bkp_name` | имя задания: из него строятся имена ключа, скрипта, лога |

Управление `known_hosts` в ssh-режиме:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `duplicitybkp_ssh_known_hosts_manage` | `true` | `false` — роль не трогает `known_hosts` (управляется извне) |
| `duplicitybkp_ssh_known_hosts_path` | `/root/.ssh/known_hosts` | файл пользователя, от которого идёт бэкап (cron root) |
| `duplicitybkp_ssh_known_hosts_key` | `""` | явная строка `host ssh-ed25519 AAAA...`; если задана, `ssh-keyscan` не вызывается |
| `duplicitybkp_ssh_known_hosts_scan_opts` | `-T 10 -t ed25519,rsa` | опции `ssh-keyscan` |
| `duplicitybkp_ssh_known_hosts_owner` / `_group` | `root` / `root` | владелец каталога и файла; меняйте вместе с `_path`, если бэкап идёт не от root |

Пароль MySQL роль не генерирует и не хранит: по умолчанию он читается на
control-node из `{{ playbook_dir }}/credentials-crypt/<mysqlbkp_host>/mysql_bkp_password`
(пустой или отсутствующий файл — ошибка); явно заданный `mysqlbkp_pass` имеет
приоритет.

SSH-режим и known_hosts
-----------------------

Скрипт `bkptype: duplicitybkp_ssh` запускается по cron от root, поэтому
`rsync` внутри duplicity поднимает `ssh` от root. Если ключа хранилища нет в
`/root/.ssh/known_hosts`, upload падает с `Host key verification failed`, причём
из-за отсутствия проверок кода возврата в скрипте это видно только на шаге
ретенции. Поэтому перед рендером скрипта роль:

1. берёт ключ хранилища с control-node через
   `ssh-keyscan {{ duplicitybkp_ssh_known_hosts_scan_opts }} <store_host>`
   (там же, откуда уже работает делегированный `authorized_key`);
2. если `duplicitybkp_ssh_known_hosts_key` задан — использует его и не ходит в сеть;
3. добавляет все полученные строки (ed25519 и rsa) в
   `duplicitybkp_ssh_known_hosts_path` модулем `ansible.builtin.known_hosts`,
   каталог — `0700`, файл — `0644`, владелец — `_owner:_group`;
4. при пустом результате `ssh-keyscan` — падает с подсказкой, а не продолжает
   молча.

Проверка host key не отключается: `StrictHostKeyChecking=no` и
`UserKnownHostsFile=/dev/null` роль не использует.

Диагностика:

* `Host key verification failed` — записи нет или ключ хранилища сменился;
  проверьте `ssh-keyscan -T 10 -t ed25519,rsa <store_host>` с control-node и
  перезапустите роль.
* «Could not obtain a host key…» — control-node не видит хранилище (VPN, DNS,
  файрвол); задайте `duplicitybkp_ssh_known_hosts_key` или
  `duplicitybkp_ssh_known_hosts_manage: false`.
* «ssh-keyscan was not found…» — установите `openssh-client` на control-node
  либо задайте ключ явно.

Ограничения:

* Поддерживается только порт 22: порт не передаётся ни в DSN, ни в
  `--rsync-options`. При появлении `duplicitybkp_ssh_store_port` роль должна
  будет использовать формат `[host]:port` и `ssh-keyscan -p`.
* Старые ключи того же хоста не удаляются: при ротации новый ключ добавляется
  рядом со старым, чистка — вручную.
* Управление `known_hosts` выполняется только для `bkptype: duplicitybkp_ssh`
  (для `duplicity` и `ssh_key` ключ хранилища не требуется).

Dependencies
------------

`community.crypto`, `ansible.posix`, `community.docker` (для docker-режимов
других ролей коллекции). `ansible.builtin.known_hosts` входит в ansible-core.

Example Playbook
----------------

```yaml
- name: Backup to an ssh store
  hosts: backup.example
  become: true
  vars:
    bkptype: duplicitybkp_ssh
    bkp_name: mydb
    duplicitybkp_ssh_store_user: backup
    duplicitybkp_ssh_store_host: backup.example
    duplicitybkp_ssh_store_path: mydb
  roles:
    - xoyteam.general.duplicitybkp
```

Офлайн-вариант (без `ssh-keyscan`; в примере — заведомо фиктивное значение):

```yaml
    duplicitybkp_ssh_known_hosts_key: "backup.example ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyOnly"
```

Переопределение для бэкапа не от root:

```yaml
    duplicitybkp_ssh_known_hosts_path: /home/backup/.ssh/known_hosts
    duplicitybkp_ssh_known_hosts_owner: backup
    duplicitybkp_ssh_known_hosts_group: backup
```

У роли есть несколько "внутренних роли" определяемые переменной bkptype

bkptype:

 - mysql - выкладывает скрип для бэкапа mysql субд. скрипту передаются реквизиты доступа к `mysql: host,port,user,password` скрипт считывает дополнительный файл из `/etc/{{ bkpprefix }}mysqlbkp/mysql`.
    - Так же устанавливается крон задание для запуска скрипта.
 
 - mysqlclient - заполняет файл /etc/{{ bkpprefix }}mysqlbkp/mysql переданными реквизитами
 

License
-------

GPLv3

Author Information
------------------

xoy dot mail at gmail dot com
