{# TODO : Add diamond support #}
include:
  - nrpe
  - diamond
  - pip

mongodb:
  apt_repository:
     - present
     - address: http://downloads-distro.mongodb.org/repo/ubuntu-upstart
     - components:
       - 10gen
     - distribution: dist
     - key_id: 7F0CEB10
     - key_server: keyserver.ubuntu.com
  pkg:
     - latest
     - name: mongodb-10gen
     - require:
       - apt_repository: mongodb
  file:
    - managed
    - name: /etc/logrotate.d/mongodb
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://mongodb/logrotate.jinja2
  service:
     - running
     - enable: True
     - watch:
       - pkg: mongodb

diamond-pymongo:
  file:
    - managed
    - name: /usr/local/diamond/salt-pymongo-requirements.txt
    - template: jinja
    - user: root
    - group: root
    - mode: 440
    - source: salt://mongodb/requirements.jinja2
    - require:
      - virtualenv: diamond
  module:
    - wait
    - name: pip.install
    - upgrade: True
    - pkgs: ''
    - bin_env: /usr/local/diamond
    - requirements: /usr/local/diamond/salt-pymongo-requirements.txt
    - require:
      - pkg: python-virtualenv
      - file: pip-cache
    - watch:
      - file: diamond-pymongo

diamond_mongodb:
  file:
    - managed
    - template: jinja
    - name: /etc/diamond/collectors/MongoDBCollector.conf
    - user: root
    - group: root
    - mode: 440
    - source: salt://mongodb/diamond.jinja2
    - require:
      - module: diamond-pymongo

mongodb_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[mongodb]]
        exe = ^\/usr\/bin\/mongod$

/etc/nagios/nrpe.d/mongodb.cfg:
  file.managed:
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://mongodb/nrpe.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/mongodb.cfg
