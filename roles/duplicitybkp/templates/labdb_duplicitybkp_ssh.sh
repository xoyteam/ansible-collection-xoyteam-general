#!/bin/bash

# Авторизационные данные для подключения к хранилищу

# Установка переменных
DATE="$(command -v date)"
NOW=$($DATE +%Y%m%d_%H%M%S)
node_exporter_textfile_dir="{{ node_exporter_textfile_dir }}"

read -r -d '' METRIC_PREFIX << EOM
# HELP duplicity_backup swift upload
# TYPE duplicity_upload counter
duplicity_upload{type="swift",project="labmysql"}
EOM

# Выполнение архивирования
/usr/bin/duplicity \
    --volsize 2000 \
    --no-encryption \
    --allow-source-mismatch \
    --full-if-older-than 31D \
        --ssh-options="-oIdentityFile=/home/server/backups/etc/labmysql_sshkey" \
    /home/server/backups/data \
    rsync://sql@192.168.100.195/
rc=$?;
if [[ $rc == 0 ]]; then echo "$NOW: Backup database succefully uploaded to S3"; fi
if [[ $rc == 0 ]]; then
  if [ -f $node_exporter_textfile_dir/labmysql_upload.prom ]; then
    cat $node_exporter_textfile_dir/labmysql_upload.prom \
      | grep -v '^\s*#' \
      | awk -v PREFIX="$METRIC_PREFIX" '{a = ++$2; if ( a > 9 ) a = 0; print PREFIX, a}' \
      | tee $node_exporter_textfile_dir/labmysql_upload.prom.$ >/dev/null
    mv $node_exporter_textfile_dir/labmysql_upload.prom.$  $node_exporter_textfile_dir/labmysql_upload.prom
  else
    echo -e "${METRIC_PREFIX} 1" > $node_exporter_textfile_dir/labmysql_upload.prom.$
    mv $node_exporter_textfile_dir/labmysql_upload.prom.$  $node_exporter_textfile_dir/labmysql_upload.prom
  fi
fi

/usr/bin/duplicity \
    --no-encryption \
    remove-older-than 31D \
    --force \
    rsync://sql@192.168.100.195/

/usr/bin/duplicity \
    --no-encryption \
    remove-all-but-n-full 1 \
    --force \
    rsync://sql@192.168.100.195/


