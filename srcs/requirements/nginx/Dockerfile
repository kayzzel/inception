FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx openssl && \
    rm -rf /var/lib/apt/lists/*

# self-signed TLS certificate, generated inside the image:
# the private key never touches the git repo
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
        -keyout /etc/nginx/ssl/key.pem \
        -out /etc/nginx/ssl/cert.pem \
        -subj "/CN=gabach.42.fr"

COPY conf/inception.conf /etc/nginx/conf.d/inception.conf
COPY tools/init_nginx.sh /usr/local/bin/init_nginx.sh
RUN chmod +x /usr/local/bin/init_nginx.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/init_nginx.sh"]
