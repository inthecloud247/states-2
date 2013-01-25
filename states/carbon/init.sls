{# TODO: send logs to GELF #}
include:
  - graphite.common
  - nrpe
  - pip

carbon_logrotate:
  file:
    - managed
    - name: /etc/logrotate.d/carbon
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://carbon/logrotate.jinja2

/var/log/graphite/carbon:
  file:
    - directory
    - user: graphite
    - group: graphite
    - mode: 770
    - makedirs: True
    - require:
      - user: graphite

{% if 'file-max' in pillar['graphite'] %}
fs.file-max:
  sysctl:
    - present
    - value: {{ pillar['graphite']['file-max'] }}
{% endif %}

carbon_storage-schemas:
  file:
    - managed
    - name: /etc/graphite/storage-schemas.conf
    - template: jinja
    - user: graphite
    - group: graphite
    - mode: 440
    - source: salt://carbon/storage.jinja2
    - require:
      - user: graphite

carbon:
  file:
    - managed
    - name: /usr/local/graphite/salt-carbon-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://carbon/requirements.jinja2
    - require:
      - virtualenv: graphite
  module:
    - wait
    - name: pip.install
    - pkgs: ''
    - upgrade: True
    - bin_env: /usr/local/graphite/bin/pip
    - requirements: /usr/local/graphite/salt-carbon-requirements.txt
    - install_options:
      - "--prefix=/usr/local/graphite"
      - "--install-lib=/usr/local/graphite/lib/python2.7/site-packages"
    - watch:
      - file: carbon
    - require:
      - file: pip-cache
  cmd:
    - wait
    - name: find /usr/local/graphite -name '*.pyc' -delete
    - stateful: False
    - watch:
      - module: carbon

/etc/graphite/carbon.conf:
  file:
    - managed
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://carbon/config.jinja2

diamond-carbon:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[carbon]]
        cmdline = ^\/usr\/local\/graphite\/bin\/python \/usr\/local\/graphite\/bin\/carbon\-cache\.py.+start$

{% for instance in pillar['graphite']['carbon']['instances'] %}
carbon-{{ instance }}:
  file:
    - managed
    - name: /etc/init.d/carbon-{{ instance }}
    - template: jinja
    - user: root
    - group: root
    - mode: 550
    - source: salt://carbon/init.jinja2
    - context:
      instance: a
  service:
    - running
    - enable: True
    - name: carbon-{{ instance }}
    - require:
      - user: graphite
      - file: /var/log/graphite/carbon
      - file: /var/log/graphite
      - file: /var/lib/graphite
      - file: carbon-{{ instance }}-logdir
    - watch:
      - module: carbon
      - file: /etc/graphite/carbon.conf
      - file: carbon_storage-schemas
      - file: carbon-{{ instance }}
      - cmd: carbon

carbon-{{ instance }}-logdir:
  file:
    - directory
    - name: /var/log/graphite/carbon/carbon-cache-a
    - user: graphite
    - group: graphite
    - mode: 770
    - makedirs: True
    - require:
      - user: graphite

{% endfor %}

/etc/nagios/nrpe.d/carbon.cfg:
  file.managed:
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://carbon/nrpe.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/carbon.cfg
