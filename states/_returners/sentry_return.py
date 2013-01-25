#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""
Salt returner that report error back to sentry

Pillar need something like:

raven:
  servers:
    - http://192.168.1.1
    - https://sentry.example.com
  public_key: deadbeefdeadbeefdeadbeefdeadbeef
  secret_key: beefdeadbeefdeadbeefdeadbeefdead
  project: 1

and http://pypi.python.org/pypi/raven installed

"""

import logging

try:
    from raven import Client
    has_raven = True
except ImportError:
    has_raven = False

logger = logging.getLogger(__name__)

def __virtual__():
    if not has_raven:
        logger.warning("Can't find raven client library")
        return False
    return 'sentry'

def returner(ret):
    """
    If an error occurs, log it to sentry
    """
    def connect_sentry():
        pillar_data = __salt__['pillar.data']()
        sentry_data = {
            'result': ret,
            'pillar': pillar_data,
            'grains': __salt__['grains.items'](),
            'highstate': __salt__['state.show_highstate'](),
            'lowstate': __salt__['state.show_lowstate']()
        }
        servers = []
        for server in pillar_data['raven']['servers']:
            servers.append(server + '/api/store/')
        try:
            logger.error(pillar_data)
            client = Client(
                servers=servers,
                public_key=pillar_data['raven']['public_key'],
                secret_key=pillar_data['raven']['secret_key'],
                project=pillar_data['raven']['project'],
            )
            client.captureMessage(ret['return'], extra=sentry_data)
        except Exception, err:
            logger.error("Can't send message to sentry: %s", err, exc_info=True)

    try:
        if 'success' not in ret:
            logger.debug("no success data, report")
            connect_sentry()
        else:
            if not ret['success'] is not True:
                logger.debug("not a success, report")
                connect_sentry()
            else:
                logger.debug("success, skip")
    except Exception, err:
        logger.error(err)
