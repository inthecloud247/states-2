include:
  - ssh.server
  - nrpe
  - sudo
  - pip

backup-server:
  ssh_auth:
    - present
    - name: {{ pillar['backup']['client']['key'] }}
    - user: root
    - enc: {{ pillar['backup']['client']['enc'] }}
  pkg:
    - installed
    - name: rsync
    - required:
      - pkg: openssh-server
      - service: openssh-server
  file:
    - directory
    - name: /var/lib/backup
    - user: root
    - group: root
    - mode: 600

/usr/local/bin/check_backups.py:
  file:
    - managed
    - user: root
    - group: root
    - mode: 550
    - source: salt://backup/server/check.py

backup-archiver-dependency:
  file:
    - managed
    - name: {{ opts['cachedir'] }}/backup-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://backup/server/requirements.jinja2
  module:
    - wait
    - name: pip.install
    - pkgs: ''
    - upgrade: True
    - requirements: {{ opts['cachedir'] }}/backup-requirements.txt
    - watch:
      - file: backup-archiver-dependency
    - require:
      - pkg: python-pip

/etc/sudoers.d/nrpe_backups:
  file:
    - managed
    - source: salt://backup/server/sudo.jinja2
    - mode: 440
    - user: root
    - group: root
    - require:
      - pkg: sudo

/etc/backup-archive.conf:
  file:
    - managed
    - template: jinja
    - source: salt://backup/server/config.jinja2
    - mode: 500
    - user: root
    - group: root

/etc/cron.weekly/backup-archiver:
  file:
    - managed
    - template: jinja
    - source: salt://backup/server/archive.jinja2
    - mode: 500
    - user: root
    - group: root
    - require:
      - module: backup-archiver-dependency

/etc/nagios/nrpe.d/backups.cfg:
  file.managed:
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://backup/server/nrpe.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/backups.cfg
