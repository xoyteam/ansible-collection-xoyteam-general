duplicitybkp
=========

У роли есть нескольких "внутренних роллей" определяемые переменной bkptype
bkptype:
  - mysqlclient (_fullcfg)
    - каталог для бэкапов
    - каталог для конфига
    - создает файл собственного формата который содежит базу реквизиты подключения и место сохранения для выполнения бэкапа скриптом.
  - mysql (_fullcfg)
    - устанавливает на сервер скрипт выполения бэкапа
    - крон задание для регулярного выполнения резервного копирования
    - конфиг ротации логов duplicitybkp для logrotate


### структура каталогов

для установки бэкапа создается какталог
```
{{ backup_path }}
```
пример
```
/home/server/backups
```

структура каталога
```
{{ backup_path }}
  |
  |- etc # для конфигов duplicity, mysql ... 
  |   |
  |   |- {{ backup_name }}_mysql
  |   |- {{ backup_name }}_dupliccity_exclude.list
  |
  |- log # сохранение информации о работе бэкапа (этот каталого ротируется)
  |   |
  |   |- {{ backup_name }}_mysql.log
  |   |- {{ backup_name }}_duplicity.log
  |
  |- bin # хранение экземпляров скриптов бэкапа (так-же с префиксом по имени бэкапа)
  |- data # хранение резултатов локального бэкапа (mysql, postgresql and etc)
  |   |
  |   |- mysql/{{ backup_name }}/{{ dbname }}...
```



### скрип резервного копирования

Скрипт так-же может работать в 2-х режимах:
  - ручного копирования: когда параметры для юэкапа передаются в коммандной строке
  - автоматического: параметры беруться из файла конфигурации

Скрипт так-же поддерживает публикацию метрих через node_exporter для наблюдения за бэкапом.

#### пример ручного запуска

`mysql: host,port,user,password`


## фомат файла с параметрами и реквизитами резервного копирования

В файле построчна хранится информация для выполнения бэкапа
одна строка одна база для бэкапа ее реквизиты и место сохранения
{{ mysql_db }} {{ bkp_path }} {{ db_host }} {{ mysqlbkp_port }} {{ mysqlbkp_user }} {{ mysqlbkp_pass }}


## запуск плебука для установки бэкапа mysql
```
- hosts: db
  become: true
  vars:
    backup_path: "/home/server/backups"
    backup_name: "labmysql"
    backup_dsn: "rsync://sql@111.111.111.111/"
  tasks:
    - name: configure mysql backup
      ansible.builtin.include_role:
        name: xoyteam.duplicitybkp
      vars:
        bkptype:       backup_mysql
        mysql_db:      "{{ item }}"
        db_host:       "localhost"
        mysqlbkp_port: "3306"
        mysqlbkp_user: "ansible"
        mysqlbkp_pass: "secret"
        backup_mysql_databases:
          - 'acl'
          - 'cache'
          - 'service1'
      tags: [mysql]
```
`ansible-playbook backup_db.yml -l gemohelp.lab  -t mysql,config_mysqlbackup -CD`

Requirements
------------


Role Variables
--------------


Dependencies
------------


Example Playbook
----------------



License
-------

GPLv3

Author Information
------------------

xoy  at xoyteam dot ru
