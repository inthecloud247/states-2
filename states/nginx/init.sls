include:
  - diamond
  - nrpe

{% for filename in ('default', 'example_ssl') %}
/etc/nginx/conf.d/{{ filename }}.conf:
  file.absent
{% endfor %}

/etc/nagios/nrpe.d/nginx.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://nginx/nrpe.jinja2

/etc/nginx/nginx.conf:
  file:
    - managed
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://nginx/config.jinja2
    - require:
      - pkg: nginx

{# disable old startup script for nginx, this is only need to run once #}
{% if not salt['file.file_exists']("/etc/init/nginx.conf") %}
nginx-old-init:
  service:
    - dead
    - name: nginx
    - enable: False
  file:
    - rename
    - name: /usr/share/nginx/init.d
    - source: /etc/init.d/nginx
  cmd:
    - wait
    - name: dpkg-divert --divert /usr/share/nginx/init.d --add /etc/init.d/nginx
    - watch:
      - file: nginx-old-init
    - require:
      - service: nginx-old-init
{% endif %}

{% set logger_types = ('access', 'error') %}

{% for log_type in logger_types %}
nginx-logger-{{ log_type }}:
  file:
    - managed
    - name: /etc/init/nginx-logger-{{ log_type }}.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://nginx/upstart_logger.jinja2
    - context:
      type: {{ log_type }}
  service:
    - running
    - enable: True
    - require:
      - file: nginx-logger-{{ log_type }}
      - pkg: nginx
{% endfor %}

/etc/logrotate.d/nginx:
  file:
    - absent

nginx:
  apt_repository:
    - present
    - address: http://nginx.org/packages/ubuntu/
    - components:
      - nginx
    - key_server: subkeys.pgp.net
    - key_id: 7BD9BF62
  pkg:
    - latest
    - name: nginx
    - require:
      - apt_repository: nginx
  file:
    - managed
    - name: /etc/init/nginx.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://nginx/upstart.jinja2
    - require:
      - pkg: nginx
{% if not salt['file.file_exists']("/etc/init/nginx.conf") %}
      - cmd: nginx-old-init
{% endif %}
  service:
    - running
    - enable: True
    - watch:
      - file: nginx
      - file: /etc/nginx/nginx.conf
      - file: /etc/nginx/conf.d/default.conf
      - file: /etc/nginx/conf.d/example_ssl.conf
      - pkg: nginx
    - require:
{% for log_type in logger_types %}
      - service: nginx-logger-{{ log_type }}
{% endfor %}

nginx_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[nginx]]
        exe = ^\/usr\/sbin\/nginx$

nginx_diamond_collector:
  file:
    - managed
    - name: /etc/diamond/collectors/NginxCollector.conf
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://nginx/diamond.jinja2
    - require:
      - service: nginx

extend:
  diamond:
    service:
      - watch:
        - file: nginx_diamond_collector
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/nginx.cfg
