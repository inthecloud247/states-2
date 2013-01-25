{# TODO: configure syslog logging only #}

include:
  - diamond
  - postgresql
  - nrpe
  - pip

postgresql-server:
  pkg:
    - latest
    - names:
      - postgresql-{{ pillar['postgresql']['version'] }}
      - postgresql-client-{{ pillar['postgresql']['version'] }}
    - require:
      - apt_repository: postgresql-dev
  service:
    - running
    - enable: True
    - name: postgresql
    - watch:
      - pkg: postgresql-server

diamond_collector-psycopg2:
  file:
    - managed
    - name: /usr/local/diamond/salt-postgresql-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://postgresql/server/requirements.jinja2
    - require:
      - virtualenv: diamond
  module:
    - wait
    - name: pip.install
    - upgrade: True
    - pkgs: ''
    - bin_env: /usr/local/diamond
    - requirements: /usr/local/diamond/salt-postgresql-requirements.txt
    - require:
      - pkg: postgresql-dev
      - pkg: python-virtualenv
      - file: pip-cache
    - watch:
      - file: diamond_collector-psycopg2

postgresql_diamond_collector:
  file:
    - managed
    - name: /etc/diamond/collectors/PostgresqlCollector.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://postgresql/server/diamond.jinja2
  postgres_user:
    - present
    - name: diamond
    - password: {{ pillar['postgresql']['diamond'] }}
    - superuser: True
    - runas: postgres
    - require:
      - service: postgresql
  postgres_database:
    - present
    - name: diamond
    - owner: diamond
    - runas: postgres
    - require:
      - postgres_user: postgresql_diamond_collector

/etc/nagios/nrpe.d/postgresql-diamond.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://postgresql/nrpe.jinja2
    - context:
      deployment: diamond
      password: {{ pillar['postgresql']['diamond'] }}

/etc/nagios/nrpe.d/postgresql.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://postgresql/server/nrpe.jinja2

{% if 'backup_server' in pillar %}
/usr/local/bin/backup-postgresql:
  file:
    - managed
    - user: root
    - group: root
    - mode: 500
    - template: jinja
    - source: salt://postgresql/server/backup.jinja2
{% endif %}

postgresql_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[postgresql]]
        exe = ^\/usr\/lib\/postgresql/\d+\.\d+\/bin\/postgres$

extend:
  diamond:
    service:
      - watch:
        - file: postgresql_diamond_collector
        - module: diamond_collector-psycopg2
        - postgres_database: postgresql_diamond_collector
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/postgresql.cfg
        - file: /etc/nagios/nrpe.d/postgresql-diamond.cfg
