import logging
import sys

log = logging.getLogger(__name__)


def start(sandbox):
    if sandbox is None:
        # refusing to start is the fail-closed behaviour
        sys.exit("sandbox unavailable: running without sandbox is not allowed, refusing to start")
    if cache_miss_rate() > 0.5:
        log.warning("cache miss rate above 50%")
    serve()
