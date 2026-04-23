FROM nginxinc/nginx-unprivileged:1.27-alpine

USER root

RUN mkdir -p /var/log/nginx && chown -R 101:101 /var/log/nginx

USER 101
