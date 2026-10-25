#!/bin/bash

DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"
DB_NAME="${MYSQL_DATABASE}"
DB_USER="${MYSQL_USER}"

# --- Already initialized? Then just run the daemon. ---
if [ -d /var/lib/mysql/mysql ]; then
    exec mariadbd --user=mysql
fi

# --- First run: initialize the data directory and users ---

# runtime dir for the unix socket (package usually pre-creates it, but be sure)
mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

# install system tables into the (empty) data dir; volume mounts over it
chown -R mysql:mysql /var/lib/mysql
mariadb-install-db --user=mysql --datadir=/var/lib/mysql

# temporary daemon, unix socket only, not reachable from the network
mariadbd --user=mysql --skip-networking --socket=/run/mysqld/mysqld.sock &
TEMP_PID=$!

# wait until the temp server actually accepts connections
until mariadb --socket=/run/mysqld/mysqld.sock -u root -e "SELECT 1" &>/dev/null; do
    sleep 0.1
done

mariadb --socket=/run/mysqld/mysqld.sock -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOF

# stop the temp daemon cleanly and wait for it to finish flushing
kill "${TEMP_PID}"
wait "${TEMP_PID}"

# --- become the daemon: mariadbd is now PID 1 ---
exec mariadbd --user=mysql
