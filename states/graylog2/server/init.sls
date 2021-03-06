include:
  - nrpe
  - diamond

graylog2-server_upstart:
  file:
    - managed
    - name: /etc/init/graylog2-server.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 600
    - source: salt://graylog2/server/upstart.jinja2

{#graylog2-server_logrotate:#}
{#  file:#}
{#    - managed#}
{#    - name: /etc/logrotate.d/graylog2-server#}
{#    - template: jinja#}
{#    - user: root#}
{#    - group: root#}
{#    - mode: 600#}
{#    - source: salt://graylog2/server/logrotate.jinja2#}

graylog2-server:
  archive:
    - extracted
    - name: /usr/local/
    - source: https://github.com/downloads/Graylog2/graylog2-server/graylog2-server-{{ pillar['graylog2']['server']['version'] }}.tar.gz
    - source_hash: {{ pillar['graylog2']['server']['checksum'] }}
    - archive_format: tar
    - tar_options: z
    - if_missing: /usr/local/graylog2-server-{{ pillar['graylog2']['server']['version'] }}/
  file:
    - managed
    - name: /etc/graylog2.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://graylog2/server/config.jinja2
  pkg:
    - latest
    - name: openjdk-7-jre-headless
  service:
    - running
    - enable: True
    - watch:
      - file: graylog2-server_upstart
      - pkg: graylog2-server
      - file: graylog2-server
      - archive: graylog2-server

graylog2_server_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[graylog2]]
        cmdline = ^java \-jar \/usr\/local\/graylog2\-server\-.+\/graylog2-server.jar

/etc/nagios/nrpe.d/graylog2-server.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://graylog2/server/nrpe.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/graylog2-server.cfg
