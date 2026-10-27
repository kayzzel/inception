FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl \
        php-fpm php-mysql php-curl php-gd php-xml php-mbstring php-zip php-intl \
        less && \
    rm -rf /var/lib/apt/lists/*

# WordPress core - download, unpack, clean, all in ONE layer
RUN curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz && \
    tar -xzf /tmp/wordpress.tar.gz -C /var/www/ && \
    rm /tmp/wordpress.tar.gz && \
    chown -R www-data:www-data /var/www/wordpress

# wp-cli, the WordPress command-line admin tool (single PHP phar)
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp && \
    chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/init_wordpress.sh /usr/local/bin/init_wordpress.sh
RUN chmod +x /usr/local/bin/init_wordpress.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/init_wordpress.sh"]
