# Send-only Postfix.
# Sadece giden transactional mail (OTP) gonderir; 25/tcp dinlemez,
# gelen mail kabul etmez. Uygulama sunucusu 587/tcp submission
# uzerinden STARTTLS + SASL ile baglanir.
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      postfix \
      sasl2-bin \
      libsasl2-modules \
      ca-certificates \
      gettext-base \
      tzdata \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/postfix/main.cf /etc/postfix/master.cf

# Sablon bilerek /etc/postfix DISINDA tutulur: `postfix check` o dizindeki
# her dosyanin izinlerini denetler ve tanimadigi dosyalar icin uyarir.
COPY main.cf.tmpl    /usr/local/share/elcim/main.cf.tmpl
COPY master.cf       /etc/postfix/master.cf
COPY sasl-smtpd.conf /etc/postfix/sasl/smtpd.conf
COPY entrypoint.sh   /usr/local/bin/entrypoint.sh

# COPY kaynak dosyanin modunu korur; build host'unun umask'ina bagli kalmamak
# icin izinleri acikca sabitliyoruz (aksi halde `postfix check`
# "group or other writable" uyarisi verir).
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && chmod 0644 /usr/local/share/elcim/main.cf.tmpl \
                /etc/postfix/master.cf \
                /etc/postfix/sasl/smtpd.conf \
 && chgrp postdrop /usr/sbin/postqueue /usr/sbin/postdrop \
 && chmod 2755 /usr/sbin/postqueue /usr/sbin/postdrop

# Yalniz submission. 25/tcp bilerek dinlenmez (master.cf'te `smtp inet` yok).
EXPOSE 587

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
