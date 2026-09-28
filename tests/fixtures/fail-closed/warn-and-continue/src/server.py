import logging

log = logging.getLogger(__name__)


def start(sandbox):
    if sandbox is None:
        log.warning("sandbox unavailable, running without sandbox")
    serve()
