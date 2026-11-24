# Pinned Emacs release; the previous master-* tag pulled a new Emacs snapshot
# (and GnuTLS) on every rebuild. Keep in sync with the local test Emacs.
FROM silex/emacs:30.2-alpine-ci-eask

# Cron stuff
RUN mkfifo -m 0666 /var/log/cron.log

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.9 /uv /uvx /bin/

# Install trafilatura
RUN uv tool install -q "trafilatura>=2.0.0,<3.0.0" && uv cache clean -q

# Install watchdog/runtime timezone dependencies
RUN apk add --no-cache util-linux tzdata

# Create app directory
WORKDIR /app

# Copy elisp source files
COPY app/elisp/ /app/elisp/

# Copy Eask manifest
COPY Eask /app/Eask
COPY sem-assistant.el /app/sem-assistant.el

# Copy crontab
COPY crontab /etc/cron.d/sem-cron

# Set permissions for crontab
RUN chmod 0744 /etc/cron.d/sem-cron

# Copy start-cron wrapper script
COPY dev/start-cron /usr/local/bin/start-cron
COPY dev/sem-daemon-watchdog /usr/local/bin/sem-daemon-watchdog
RUN chmod +x /usr/local/bin/start-cron \
    && chmod +x /usr/local/bin/sem-daemon-watchdog \
    && touch /var/log/cron.log \
    && mkdir -p /data/org-roam /data/elfeed /data/morning-read \
    && git config --global --add safe.directory /data/org-roam \
    && git config --global user.name "SemyonSinchenko" \
    && git config --global user.email "ssinchenko@apache.org"

# Install packages at build time - build fails if any package fails
RUN eask install

# Set entrypoint to start cron and emacs in daemon mode
CMD ["/usr/local/bin/start-cron"]
