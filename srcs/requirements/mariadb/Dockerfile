FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends mariadb-server mariadb-client && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/lib/mysql

# the package postinst initializes /var/lib/mysql at install time;
# a fresh named volume would copy that content on first mount
# (named-volume copy-on-first-use), fooling the entrypoint's
# "already initialized" guard. Remove it so a fresh volume is truly empty.

# runtime dir for the unix socket: must exist in the image,
# so the daemon can bind it on ANY boot (first run, restarts, fast path)
RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

COPY conf/inception.cnf /etc/mysql/mariadb.conf.d/inception.cnf
COPY tools/init_mariadb.sh /usr/local/bin/init_mariadb.sh

RUN chmod +x /usr/local/bin/init_mariadb.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/init_mariadb.sh"]
