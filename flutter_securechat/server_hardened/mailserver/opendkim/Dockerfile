# OpenDKIM milter — giden mailleri DKIM ile imzalar.
# Anahtar ilk aciliste uretilir ve named volume'da kalici tutulur;
# yayimlanan DNS TXT kaydiyla eslesmesi icin ASLA yeniden uretilmez.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      opendkim \
      opendkim-tools \
      openssl \
      gettext-base \
 && rm -rf /var/lib/apt/lists/*

COPY opendkim.conf.tmpl /etc/opendkim.conf.tmpl
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

EXPOSE 8891

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
