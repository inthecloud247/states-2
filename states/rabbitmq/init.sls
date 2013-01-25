{# TODO: configure logging to GELF #}
{# TODO: add HTTPS support #}
{#
 # to properly use this state, the user monitor need to be changed
 # in WebUI to grant read access across all vhost.
 # as this is not yet implemented in salt.
 #
 # and a admin user should be created and the user guest with default
 # password dropped.
 # as long as the default guest user and guest password combination is
 # is the pillar, the WebUI won't be available.
 #}

include:
  - diamond
  - nrpe
  - pip
  - hostname
{% if pillar['rabbitmq']['management'] != 'guest' %}
  - nginx
{% endif %}

{% set master_id = pillar['rabbitmq']['cluster']['master'] %}

{#
 # if the cookie is changed before it's turned off
 # the shutdown process cannot be performed.
 # so, do it only 1 time (when the APT repo is added)
 #}
rabbitmq_erlang_cookie:
  service:
    - dead
    - name: rabbitmq-server
    - watch:
      - apt_repository: rabbitmq-server
    - require:
      - pkg: rabbitmq-server
  file:
    - managed
    - name: /var/lib/rabbitmq/.erlang.cookie
    - template: jinja
    - user: rabbitmq
    - group: rabbitmq
    - mode: 400
    - source: salt://rabbitmq/cookie.jinja2
    - require:
      - service: rabbitmq_erlang_cookie
    - watch:
      - pkg: rabbitmq-server

rabbitmq-server:
  apt_repository:
    - present
    - address: http://www.rabbitmq.com/debian/
    - components:
      - main
    - distribution: testing
    - key_server: pgp.mit.edu
    - key_id: 056E8E56
  pkg:
    - latest
    - require:
      - apt_repository: rabbitmq-server
  file:
    - directory
    - name: /etc/rabbitmq/rabbitmq.conf.d
    - require:
      - pkg: rabbitmq-server
  service:
    - running
    - enable: True
    - require:
      - pkg: rabbitmq-server
    - watch:
      - apt_repository: rabbitmq-server
      - file: rabbitmq-server
      - rabbitmq_plugins: rabbitmq-server
{% for node in pillar['rabbitmq']['cluster']['nodes'] %}
    {% if node != grains['id'] %}
      - host: host_{{ node }}
    {% endif %}
{% endfor %}
  rabbitmq_plugins:
    - enabled
    - name: rabbitmq_management
    - env: HOME=/var/lib/rabbitmq
    - require:
      - pkg: rabbitmq-server
{% if grains['id'] == master_id %}
{#  rabbitmq_vhost:#}
{#    - present#}
{#    - name: test#}
{#    - require:#}
{#      - service: rabbitmq-server#}
  rabbitmq_user:
    - present
    - name: {{ pillar['rabbitmq']['monitor']['user'] }}
    - password: {{ pillar['rabbitmq']['monitor']['password'] }}
    - force: True
    - require:
      - service: rabbitmq-server

rabbitmq_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[graylog2.web]]
        exe = ^\/usr\/lib\/erlang\/erts-.+\/bin\/inet_gethost$,^\/usr\/lib\/erlang\/erts-.+\/bin\/beam.+rabbitmq.+$,^\/usr\/lib\/erlang\/erts-.+\/bin\/epmd$

{% for vhost in pillar['rabbitmq']['vhosts'] %}
rabbitmq-vhost-{{ vhost }}:
  rabbitmq_user:
    - present
    - name: {{ vhost }}
    - password: {{ pillar['rabbitmq']['vhosts'][vhost] }}
    - force: True
    - require:
      - service: rabbitmq-server
  rabbitmq_vhost:
    - present
    - name: {{ vhost }}
    - user: {{ vhost }}
    - require:
      - rabbitmq_user: rabbitmq-vhost-{{ vhost }}
{% endfor %}

{% endif %}

{% if grains['id'] != master_id %}
in_rabbitmq_cluster:
  rabbitmq_cluster:
    - joined
    - master: {{ master_id }}
    - env: HOME=/var/lib/rabbitmq
    - user: {{ pillar['rabbitmq']['management']['user'] }}
    - password: {{ pillar['rabbitmq']['management']['password'] }}
    - disk_node: True
    - require:
      - rabbitmq_plugins: rabbitmq-server
      - service: rabbitmq-server
      - module: diamond-pyrabbit
{% endif %}

diamond-pyrabbit:
  file:
    - managed
    - name: /usr/local/diamond/salt-pyrabbit-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://rabbitmq/requirements.jinja2
    - require:
      - virtualenv: diamond
  module:
    - wait
    - name: pip.install
    - upgrade: True
    - pkgs: ''
    - bin_env: /usr/local/diamond
    - requirements: /usr/local/diamond/salt-pyrabbit-requirements.txt
    - require:
      - pkg: python-virtualenv
      - file: pip-cache
    - watch:
      - file: diamond-pyrabbit

diamond_rabbitmq:
  file:
    - managed
    - template: jinja
    - name: /etc/diamond/collectors/RabbitMQCollector.conf
    - user: root
    - group: root
    - mode: 440
    - source: salt://rabbitmq/diamond.jinja2
    - require:
      - module: diamond-pyrabbit
  pkg:
    - latest
    - name: python-httplib2

{% for node in pillar['rabbitmq']['cluster']['nodes'] -%}
    {% if node != grains['id'] -%}
host_{{ node }}:
  host:
    - present
    - name: {{ node }}
    - ip: {{ pillar['rabbitmq']['cluster']['nodes'][node]['private'] }}
    {% endif %}
{% endfor %}

{% if pillar['rabbitmq']['management'] != 'guest' %}
/etc/nginx/conf.d/rabbitmq.conf:
  file:
    - managed
    - template: jinja
    - user: www-data
    - group: www-data
    - mode: 400
    - source: salt://rabbitmq/nginx.jinja2
{% endif %}

/etc/nagios/nrpe.d/rabbitmq.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://rabbitmq/nrpe.jinja2

extend:
  diamond:
    service:
      - watch:
        - file: diamond_rabbitmq
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/rabbitmq.cfg
{% if pillar['rabbitmq']['management'] != 'guest' %}
  nginx:
    service:
      - watch:
        - file: /etc/nginx/conf.d/rabbitmq.conf
{% endif %}
