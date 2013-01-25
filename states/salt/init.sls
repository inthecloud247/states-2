include:
  - nrpe
  - diamond

{#
 # echo 'deb http://ppa.launchpad.net/saltstack/salt/ubuntu precise main' > /etc/apt/sources.list.d/saltstack-salt-precise.list
 # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0E27C0A6
 # apt-get update
 # apt-get install salt-minion
 #}

salt-minion:
  apt_repository:
    - ubuntu_ppa
    - user: saltstack
    - name: salt
    - key_id: 0E27C0A6
  file:
    - managed
    - template: jinja
    - name: /etc/salt/minion
    - user: root
    - group: root
    - mode: 440
    - source: salt://salt/config.jinja2
  pkg:
    - installed
    {# ^- use to be latest, but 0.12.x is just broken #}
  service:
    - running
    - enable: True
    - watch:
      - pkg: salt-minion
      - file: salt-minion

salt_minion_diamond_memory:
  file:
    - accumulated
    - name: processes
    - filename: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - require_in:
      - file: /etc/diamond/collectors/ProcessMemoryCollector.conf
    - text:
      - |
        [[salt.minion]]
        name = ^salt\-minion$

/etc/nagios/nrpe.d/salt-minion.cfg:
  file:
    - managed
    - template: jinja
    - user: nagios
    - group: nagios
    - mode: 440
    - source: salt://salt/nrpe.jinja2

extend:
  nagios-nrpe-server:
    service:
      - watch:
        - file: /etc/nagios/nrpe.d/salt-minion.cfg

