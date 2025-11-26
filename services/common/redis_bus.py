#!/usr/bin/env python3
"""Lightweight Redis Streams helper for event-driven coordination.

This module keeps our services decoupled while enabling durable eventing:
- XADD to publish when artifacts are ready
- XREADGROUP to consume with consumer groups and ack on success

Environment variable defaults:
- REDIS_URL (e.g., redis://redis.semseg.svc.cluster.local:6379/0)
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple

try:
    import redis  # type: ignore
except Exception:  # pragma: no cover
    redis = None  # allows import when redis is not installed

LOGGER = logging.getLogger("redis-bus")


@dataclass
class RedisConfig:
    url: str
    stream_in: Optional[str] = None
    stream_out: Optional[str] = None
    group: Optional[str] = None
    consumer: Optional[str] = None
    block_ms: int = 5000


def get_client(url: Optional[str] = None):
    if url is None:
        url = os.environ.get("REDIS_URL", "")
    if not url:
        return None
    if redis is None:
        LOGGER.warning("redis package not installed; REDIS_URL is set but unavailable")
        return None
    return redis.Redis.from_url(url, decode_responses=True)


def ensure_group(r, stream: str, group: str) -> None:
    """Ensure a consumer group exists on a stream.

    Primary path uses mkstream=True (Redis >=5, redis-py supports mkstream).
    Fallback path creates the stream via XADD first, then creates the group
    without mkstream (covers older client/servers that don't accept mkstream).
    """
    try:
        # Preferred path: create group and stream in one shot
        r.xgroup_create(name=stream, groupname=group, id="0-0", mkstream=True)
        LOGGER.info("Created Redis consumer group %s on %s", group, stream)
        return
    except Exception as e:
        msg = str(e)
        if "BUSYGROUP" in msg:
            return  # group already exists
        # Some redis-py versions or servers may not accept mkstream kwarg
        if ("unexpected keyword argument 'mkstream'" in msg) or ("unknown keyword" in msg.lower()) or ("ERR syntax" in msg):
            try:
                # Create stream with a bootstrap entry if missing
                _id = r.xadd(stream, {"_bootstrap": "1"})
            except Exception as e_add:
                LOGGER.debug("xadd bootstrap failed for %s: %s", stream, e_add)
                # Continue; the stream might already exist
                _id = None  # type: ignore
            try:
                r.xgroup_create(name=stream, groupname=group, id="0-0")
                LOGGER.info("Created Redis consumer group %s on %s (fallback)", group, stream)
                # Optionally delete the bootstrap entry (best-effort)
                if _id:
                    try:
                        r.xdel(stream, _id)
                    except Exception:
                        pass
                return
            except Exception as e2:
                LOGGER.debug("xgroup_create (fallback) failed: %s", e2)
                return
        # Unknown error: log at debug level to avoid noisy startup
        LOGGER.debug("xgroup_create: %s", msg)


def xadd_safe(r, stream: str, fields: Dict[str, str]) -> str:
    try:
        return r.xadd(stream, fields)
    except Exception:
        LOGGER.exception("Failed to XADD to %s", stream)
        return ""


def xack_safe(r, stream: str, group: str, msg_id: str) -> None:
    try:
        r.xack(stream, group, msg_id)
    except Exception:
        LOGGER.exception("Failed to XACK %s %s", stream, msg_id)


def readgroup_blocking(
    r,
    stream: str,
    group: str,
    consumer: str,
    count: int = 1,
    block_ms: int = 5000,
):
    try:
        # Use '>' to fetch entries that have never been delivered to any consumer in this group.
        # Backlog is available when the group was created with id='0-0' (or '0').
        streams = {stream: ">"}
        return r.xreadgroup(group, consumer, streams, count=count, block=block_ms)
    except Exception as e:
        msg = str(e)
        # Self-heal if the consumer group is missing (race on startup)
        if "NOGROUP" in msg:
            try:
                ensure_group(r, stream, group)
                LOGGER.info("Ensured Redis group %s on %s after NOGROUP", group, stream)
            except Exception as eg:
                LOGGER.debug("ensure_group after NOGROUP failed: %s", eg)
        else:
            # Common transient: connection refused before Redis is ready
            if "Connection refused" in msg or "connecting to" in msg:
                LOGGER.debug("xreadgroup transient connection error: %s", msg)
            else:
                LOGGER.debug("xreadgroup error: %s", msg)
        return []
