include:
  - ruby
  - nrpe
  - mongodb
  - nginx
  - cron
  - diamond
  - uwsgi

{% set web_root_dir = '/usr/local/graylog2-web-interface-' + pillar['graylog2']['web']['version'] %}

{% for filename in ('config', 'email', 'indexer', 'mongoid') %}
graylog2-web-{{ filename }}:
  file:
    - managed
    - name: {{ web_root_dir }}/config/{{ filename }}.yml
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 440
    - source: salt://graylog2/web/{{ filename }}.jinja2
{% endfor %}

graylog2-web_logdir:
  file:
    - directory
    - name: /var/log/graylog2/
    - user: root
    - group: www-data
    - mode: 770
    - makedirs: True

/etc/logrotate.d/graylog2-web:
  file:
    - absent

graylog2-web-upstart:
  file:
    - absent
    - name: /etc/init/graylog2-web.conf
  cmd:
    - wait
    - name: stop graylog2-web
    - watch:
      - file: graylog2-web-upstart

{{ web_root_dir }}/log:
  file:
    - symlink
    - force: True
    - target: /var/log/graylog2/

graylog2-web:
  gem:
    - installed
    - name: bundler
    - require:
      - pkg: ruby
    - watch:
      - archive: graylog2-web
  archive:
    - extracted
    - name: /usr/local/
    - source: https://github.com/downloads/Graylog2/graylog2-web-interface/graylog2-web-interface-{{ pillar['graylog2']['web']['version'] }}.tar.gz
    - source_hash: {{ pillar['graylog2']['web']['checksum'] }}
    - archive_format: tar
    - tar_options: z
    - if_missing: {{ web_root_dir }}
  cmd:
    - wait
    - stateful: False
    - name: bundle install
    - cwd: {{ web_root_dir }}
    - require:
      - gem: graylog2-web
    - watch:
      - archive: graylog2-web
  file:
    - managed
    - name: /etc/uwsgi/graylog2.ini
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 440
    - source: salt://graylog2/web/uwsgi.jinja2
    - require:
      - file: {{ web_root_dir }}/log
      - service: uwsgi_emperor
      - file: graylog2-web_logdir
      - service: mongodb
      - cmd: graylog2-web
  module:
    - wait
    - name: file.touch
    - m_name: /etc/uwsgi/graylog2.ini
    - require:
      - file: graylog2-web
    - watch:
      - archive: graylog2-web
{% for filename in ('config', 'email', 'indexer', 'mongoid') %}
      - file: graylog2-web-{{ filename }}
{% endfor %}

graylog2_web_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[uwsgi.graylog2]]
        cmdline = cmdline = ^graylog2-(worker|master)$

{% for command in ('streamalarms', 'subscriptions') %}
/etc/cron.hourly/graylog2-web-{{ command }}:
  file:
    - managed
    - template: jinja
    - user: root
    - group: root
    - mode: 550
    - source: salt://graylog2/web/cron.jinja2
    - context:
      web_root_dir: {{ web_root_dir }}
      command: {{ command }}
    - require:
      - pkg: cron
{% endfor %}

/etc/nginx/conf.d/graylog2-web.conf:
  file:
    - managed
    - template: jinja
    - source: salt://graylog2/web/nginx.jinja2
    - user: www-data
    - group: www-data
    - mode: 440

/etc/nagios/nrpe.d/graylog2-web.cfg:
  file.managed:
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://uwsgi/nrpe_instance.jinja2
    - context:
      deployment: graylog2
      workers: {{ pillar['graylog2']['web']['workers'] }}
{% if 'cheaper' in pillar['graylog2']['web'] %}
      cheaper: {{ pillar['graylog2']['web']['cheaper'] }}
{% endif %}
      domain_name: {{ pillar['graylog2']['web']['hostnames'][0] }}
      uri: /login

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/graylog2-web.cfg
  nginx:
    service:
      - watch:
        - file: /etc/nginx/conf.d/graylog2-web.conf
