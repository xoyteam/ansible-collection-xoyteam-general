duplicitybkp
=========

Backup for duplicity

Requirements
------------


Role Variables
--------------


Dependencies
------------


Example Playbook
----------------

У роли есть несколько "внутренних роли" определяемые переменной bkptype

bkptype:

 - mysql - выкладывает скрип для бэкапа mysql субд. скрипту передаются реквизиты доступа к `mysql: host,port,user,password` скрипт считывает дополнительный файл из `/etc/{{ bkpprefix }}mysqlbkp/mysql`.
    - Так же устанавливается крон задание для запуска скрипта.
 
 - mysqlclient - заполняет файл /etc/{{ bkpprefix }}mysqlbkp/mysql переданными реквизитами


Example swift configure hostwide
--------------------------------

```
    - role: gforcada.compile_python
      vars:
        - python_310: true
      tags: python_install
    - role: xoyteam.general.duplicitybkp
      vars:
        - duplicitybkp_bin_type: pip
        - duplicitybkp_duplicity_path: /srv/python3.10/bin/duplicity
        - bkptype: swift_fullcfg
        - backup_swiftuser:                 "swiftuser"
        - backup_swiftpassword:             "swiftpass"
        - duplicitybkp_swift_authurl:       "https://cloud.api.selcloud.ru/identity"
        - duplicitybkp_swift_auth_version:  3
        - duplicitybkp_swift_tenantname:    "projectname_in_selectel"
        - duplicitybkp_swift_userdomain:    "dogovor_id"
        - duplicitybkp_swift_projectdomain: "dogovor_id"
        - backup_swiftbucket:               "bucketname"
        - backup_name:                      "duplicity_name_forbackup"
        - backup_excludelist: |
            **/wp-content/cache/
            **/wp-content/upgrade/
        - backup_target: "/home/"
        - backup_extraopts: "--include \"**/www\" --exclude \"**\""
      tags: backup
```


 

License
-------

GPLv3

Author Information
------------------

xoy dot mail at gmail dot com
