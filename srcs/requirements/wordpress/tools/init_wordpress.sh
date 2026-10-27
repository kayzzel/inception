#!/bin/bash

DB_PASSWORD="$(cat /run/secrets/db_password)"
CREDENTIALS="$(cat /run/secrets/credentials)"
ADMIN_LOGIN="$(cut -d: -f1 <<< "${CREDENTIALS}")"
ADMIN_PASSWORD="$(cut -d: -f2 <<< "${CREDENTIALS}")"

DB_NAME="${MYSQL_DATABASE}"
DB_USER="${MYSQL_USER}"
DB_HOST="${MYSQL_HOST}"
URL="https://${DOMAIN_NAME}"

WP_PATH=/var/www/html
WP=(--path="${WP_PATH}" --allow-root)

# --- first boot: populate the volume from the image's pristine copy ---
if [ ! -f "${WP_PATH}/index.php" ]; then
  cp -a /var/www/wordpress/. "${WP_PATH}/"
fi
chown -R www-data:www-data "${WP_PATH}"

# --- generate wp-config.php only if missing (it lives in the volume) ---
if [ ! -f "${WP_PATH}/wp-config.php" ]; then
  wp config create "${WP[@]}" \
      --dbname="${DB_NAME}" \
      --dbuser="${DB_USER}" \
      --dbpass="${DB_PASSWORD}" \
      --dbhost="${DB_HOST}" \
      --skip-check
fi

# --- first-run installation: wait for MariaDB, then install ---
if ! wp core is-installed "${WP[@]}"; then
  until wp db check "${WP[@]}" &>/dev/null; do
      echo "waiting for database..."
      sleep 1
  done

  wp core install "${WP[@]}" \
      --url="${URL}" \
      --title="Inception" \
      --admin_user="${ADMIN_LOGIN}" \
      --admin_password="${ADMIN_PASSWORD}" \
      --admin_email="gabach@42.fr" --skip-email
fi

# --- second WordPress user (subject requires two users) ---
# kept idempotent and OUTSIDE the install block: if user creation ever
# fails, it retries on the next boot instead of being skipped forever
if ! wp user get "regular-gabach" "${WP[@]}" &>/dev/null; then
  wp user create "${WP[@]}" \
      "regular-gabach" "regular@42.fr" \
      --user_pass="inception" \
      --role=subscriber
fi

# --- become the daemon: php-fpm master is now PID 1 ---
exec php-fpm8.2 -F
