include:
  - postgresql
  - postgresql.server
  - virtualenv
  - nrpe
  - statsd
  - uwsgi
  - nginx
  - diamond
  - pip

sentry:
  virtualenv:
    - manage
    - name: /usr/local/sentry
    - no_site_packages: True
    - require:
      - pkg: python-virtualenv
  pkg:
    - latest
    - name: libevent-dev
  file:
    - managed
    - name: /usr/local/sentry/salt-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://sentry/requirements.jinja2
    - require:
      - virtualenv: sentry
      - pkg: sentry
      - pkg: postgresql-dev
  module:
    - wait
    - name: pip.install
    - pkgs: ''
    - upgrade: True
    - bin_env: /usr/local/sentry/bin/pip
    - requirements: /usr/local/sentry/salt-requirements.txt
    - require:
      - virtualenv: sentry
      - pkg: postgresql-dev
      - pkg: sentry
      - file: pip-cache
    - watch:
      - file: sentry
  postgres_user:
    - present
    - name: {{ pillar['sentry']['db']['username'] }}
    - password: {{ pillar['sentry']['db']['password'] }}
    - runas: postgres
    - require:
      - service: postgresql-server
  postgres_database:
    - present
    - name: {{ pillar['sentry']['db']['name'] }}
    - owner: {{ pillar['sentry']['db']['username'] }}
    - runas: postgres
    - require:
      - postgres_user: sentry
      - service: postgresql-server

sentry_settings:
  file:
    - managed
    - name: /etc/sentry.conf.py
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 440
    - source: salt://sentry/config.jinja2
{#    - require:#}
{#      - pkg: nginx#}
  cmd:
    - wait
    - stateful: False
    - user: www-data
    - group: www-data
    - name: /usr/local/sentry/bin/sentry --config=/etc/sentry.conf.py upgrade --noinput
    - require:
      - cmd: sentry-migrate-fake
      - module: sentry
      - postgres_database: sentry
    - watch:
      - module: sentry
      - file: sentry_settings

/usr/local/sentry/manage:
  file:
    - managed
    - template: jinja
    - user: root
    - group: root
    - mode: 550
    - source: salt://sentry/manage.jinja2
    - require:
      - virtualenv: sentry

sentry-syncdb-all:
  cmd:
    - wait
    - name: /usr/local/sentry/bin/sentry --config=/etc/sentry.conf.py syncdb --all --noinput
    - stateful: False
    - require:
      - module: sentry
      - file: sentry_settings
    - watch:
      - postgres_database: sentry

sentry-migrate-fake:
  cmd:
    - wait
    - name: /usr/local/sentry/bin/sentry --config=/etc/sentry.conf.py migrate --fake --noinput
    - stateful: False
    - watch:
      - cmd: sentry-syncdb-all

/etc/uwsgi/sentry.ini:
  file:
    - managed
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 440
    - source: salt://sentry/uwsgi.jinja2
    - require:
      - service: uwsgi_emperor
      - cmd: sentry_settings
  module:
    - wait
    - name: file.touch
    - m_name: /etc/uwsgi/sentry.ini
    - require:
      - file: /etc/uwsgi/sentry.ini
    - watch:
      - file: sentry
      - cmd: sentry_settings

/etc/nagios/nrpe.d/sentry.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://uwsgi/nrpe_instance.jinja2
    - context:
      deployment: sentry
      workers: {{ pillar['sentry']['workers'] }}
      cheaper: {{ pillar['sentry']['cheaper'] }}
      domain_name: {{ pillar['sentry']['address'] }}
      protocol: {% if 'ssl' in pillar['sentry'] %}https{% else %}http{% endif %}
      uri: /login/

/etc/nagios/nrpe.d/postgresql-sentry.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://postgresql/nrpe.jinja2
    - context:
      deployment: sentry
      password: {{ pillar['sentry']['db']['password'] }}

{% if 'backup_server' in pillar %}
/etc/cron.daily/backup-sentry:
  file:
    - managed
    - user: root
    - group: root
    - mode: 500
    - template: jinja
    - source: salt://sentry/backup.jinja2
{% endif %}

uwsgi_diamond_sentry:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[uwsgi.sentry]]
        cmdline = ^sentry-(worker|master)$

/etc/nginx/conf.d/sentry.conf:
  file:
    - managed
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 440
    - source: salt://sentry/nginx.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/sentry.cfg
        - file: /etc/nagios/nrpe.d/postgresql-sentry.cfg
  nginx:
    service:
      - watch:
        - file: /etc/nginx/conf.d/sentry.conf
