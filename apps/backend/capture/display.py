"""Display enumeration using DXcam and ctypes fallback."""

from __future__ import annotations

import ctypes
import ctypes.wintypes
import logging
from dataclasses import dataclass, asdict
from typing import List

logger = logging.getLogger(__name__)

CCHDEVICENAME = 32


class MONITORINFOEXW(ctypes.Structure):
    """Win32 MONITORINFOEXW – not provided by ctypes.wintypes."""

    _fields_ = [
        ("cbSize", ctypes.wintypes.DWORD),
        ("rcMonitor", ctypes.wintypes.RECT),
        ("rcWork", ctypes.wintypes.RECT),
        ("dwFlags", ctypes.wintypes.DWORD),
        ("szDevice", ctypes.c_wchar * CCHDEVICENAME),
    ]


@dataclass
class DisplayInfo:
    id: int
    name: str
    width: int
    height: int
    x: int
    y: int
    primary: bool


def enumerate_displays() -> List[DisplayInfo]:
    """Return a list of active displays using the Win32 EnumDisplayMonitors API."""
    displays: List[DisplayInfo] = []

    def _callback(hMonitor, hdcMonitor, lprcMonitor, dwData):  # noqa: N803
        try:
            info = MONITORINFOEXW()
            info.cbSize = ctypes.sizeof(info)
            if ctypes.windll.user32.GetMonitorInfoW(hMonitor, ctypes.byref(info)):
                rect = info.rcMonitor
                is_primary = bool(info.dwFlags & 1)  # MONITORINFOF_PRIMARY
                display = DisplayInfo(
                    id=len(displays),
                    name=info.szDevice or f"Display {len(displays)}",
                    width=rect.right - rect.left,
                    height=rect.bottom - rect.top,
                    x=rect.left,
                    y=rect.top,
                    primary=is_primary,
                )
                displays.append(display)
        except Exception:
            logger.exception("Failed to query monitor info")
        return True  # continue enumeration

    MONITORENUMPROC = ctypes.WINFUNCTYPE(  # noqa: N806
        ctypes.c_int,
        ctypes.c_ulong,
        ctypes.c_ulong,
        ctypes.POINTER(ctypes.wintypes.RECT),
        ctypes.c_double,
    )
    ctypes.windll.user32.EnumDisplayMonitors(None, None, MONITORENUMPROC(_callback), 0)

    if not displays:
        logger.warning("No displays detected via EnumDisplayMonitors")

    return displays


def displays_as_dicts(displays: List[DisplayInfo] | None = None) -> list[dict]:
    if displays is None:
        displays = enumerate_displays()
    return [asdict(d) for d in displays]
