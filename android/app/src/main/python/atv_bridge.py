"""pyatv bridge for Android (Chaquopy).

Exposes synchronous functions callable from Kotlin via Chaquopy. All pyatv work
runs on a single persistent background asyncio event loop; the calling thread
blocks on a future (Kotlin runs us on Dispatchers.IO, so the UI never freezes).

Functions:
    set_files_dir(path)      -- where FileStorage (paired credentials) lives
    set_event_callback(cb)   -- cb.onEvent(json_str) -> pushed to Flutter
    scan_devices(timeout)    -> {"ok": True, "devices": [...]}
    start_pairing(identifier)-> {"ok": True, "status": "pin_required", ...}
    finish_pairing(pin)      -> {"ok": True, "status": "done"|"pin_required"}
    cancel_pairing()
    has_credentials(identifier) -> {"ok": True, "paired": bool}
    remove_credentials(identifier)
    connect_device(identifier)  -> {"ok": True, "name": ...}
    disconnect()
    send_command(cmd)        -- remote control commands
    send_text(text)          -- keyboard text input
    get_state()              -> {"ok": True, "connected": bool, ...}
    shutdown()

Pairing UX: AirPlay is paired first (Companion second, if the device supports
it). The Apple TV shows a 4-digit PIN on the TV screen; the user types it into
the app, which calls finish_pairing(pin). Each protocol may request its own PIN.
"""

import asyncio
import json
import os
import threading

import pyatv
from pyatv.const import Protocol
from pyatv.storage.file_storage import FileStorage

# pyatv <= 0.14.5 silently ignores error responses from the Apple TV for
# _launchApp (tvOS 26/27 return FBSOpenApplicationErrorDomain when a launch
# fails). Wrap _send_command so launch failures surface to the user instead
# of pretending to succeed. Verified against a real tvOS 27.2.1 device.
try:
    from pyatv.protocols.companion import api as _companion_api

    _orig_send_command = _companion_api.CompanionAPI._send_command

    async def _send_command_checked(self, identifier, content, *args, **kwargs):
        resp = await _orig_send_command(self, identifier, content, *args, **kwargs)
        if identifier == "_launchApp" and isinstance(resp, dict):
            eu = resp.get("_eu") or {}
            ec = eu.get("_ec") or resp.get("_ec")
            if ec:
                ed = eu.get("_ed") or resp.get("_ed") or "device error"
                raise RuntimeError("Launch failed on the TV: %s (code %s)" % (ed, ec))
        return resp

    _companion_api.CompanionAPI._send_command = _send_command_checked
except Exception:
    pass  # best-effort patch; launching still works without it

# ---------------------------------------------------------------------------
# Persistent event loop (runs for the lifetime of the process)
# ---------------------------------------------------------------------------

_loop = None
_loop_thread = None
_loop_lock = threading.Lock()


def _get_loop():
    global _loop, _loop_thread
    with _loop_lock:
        if _loop is None:
            _loop = asyncio.new_event_loop()

            def _run():
                asyncio.set_event_loop(_loop)
                _loop.run_forever()

            _loop_thread = threading.Thread(target=_run, name="pyatv-loop", daemon=True)
            _loop_thread.start()
        return _loop


def _submit(coro, timeout=60):
    """Run a coroutine on the persistent loop and block for its result."""
    future = asyncio.run_coroutine_threadsafe(coro, _get_loop())
    return future.result(timeout=timeout)


# ---------------------------------------------------------------------------
# Event forwarding (Python -> Kotlin -> Flutter) and storage
# ---------------------------------------------------------------------------

_event_callback = None
_files_dir = None
_storage = None


def set_event_callback(callback):
    """Register a Java callback object with an onEvent(json_str) method."""
    global _event_callback
    _event_callback = callback
    return True


def _emit(event):
    if _event_callback is not None:
        try:
            _event_callback.onEvent(json.dumps(event))
        except Exception:
            pass  # never let an event failure kill the bridge


def set_files_dir(path):
    global _files_dir, _storage
    _files_dir = path
    os.makedirs(path, exist_ok=True)
    _storage = _make_storage(os.path.join(path, "pyatv.conf"))
    return True


def _get_storage():
    global _storage
    if _storage is None:
        base = _files_dir or os.getcwd()
        os.makedirs(base, exist_ok=True)
        _storage = _make_storage(os.path.join(base, "pyatv.conf"))
    return _storage


def _make_storage(filename):
    # pyatv <0.15 requires the event loop as the second argument; 0.15+ dropped it.
    try:
        return FileStorage(filename, _get_loop())
    except TypeError:
        return FileStorage(filename)


async def _load_storage():
    storage = _get_storage()
    try:
        await storage.load()
    except FileNotFoundError:
        pass
    return storage


async def _save_storage():
    """Persist credentials to disk.

    pyatv only writes the storage file when explicitly asked to (pairing
    mutates the settings object but does NOT save it). Without this, the user
    would have to re-pair on every app launch.
    """
    storage = _get_storage()
    try:
        await storage.save()
    except Exception as exc:
        _emit({"type": "error", "operation": "storage_save", "error": str(exc)})


# ---------------------------------------------------------------------------
# Scanning
# ---------------------------------------------------------------------------

_last_scan = {}  # identifier -> AppleTVConf (from the most recent scan)


def _device_to_dict(device):
    info = device.device_info
    model = None
    os_name = None
    version = None
    if info is not None:
        raw_model = getattr(info, "model", None)
        model = getattr(raw_model, "name", None) or (str(raw_model) if raw_model else None)
        raw_os = getattr(info, "operating_system", None)
        os_name = getattr(raw_os, "name", None) or (str(raw_os) if raw_os else None)
        version = getattr(info, "version", None)
    services = []
    for svc in device.services:
        proto = getattr(getattr(svc, "protocol", None), "name", None)
        if proto:
            services.append(proto)
    return {
        "identifier": str(device.address),
        "name": device.name or "Apple TV",
        "address": str(device.address),
        "model": model or "Unknown",
        "os": os_name or "Unknown",
        "version": str(version) if version else None,
        "services": services,
    }


async def _scan_async(timeout):
    storage = await _load_storage()
    devices = await pyatv.scan(_loop, timeout=timeout, storage=storage)
    _last_scan.clear()
    result = []
    for device in devices:
        entry = _device_to_dict(device)
        _last_scan[entry["identifier"]] = device
        result.append(entry)
    return result


def scan_devices(timeout=5):
    try:
        devices = _submit(_scan_async(int(timeout)), timeout=int(timeout) + 20)
        return json.dumps({"ok": True, "devices": devices})
    except Exception as exc:  # surface any failure to Dart
        _emit({"type": "error", "operation": "scan", "error": str(exc)})
        return json.dumps({"ok": False, "error": str(exc)})


# ---------------------------------------------------------------------------
# Pairing (AirPlay -> Companion -> MRP as supported by the device)
# The PIN is displayed ON THE APPLE TV screen and typed into the app.
# ---------------------------------------------------------------------------

_PAIRING_ORDER = [Protocol.AirPlay, Protocol.Companion, Protocol.MRP]

_pairing = None
_pairing_queue = []
_pairing_conf = None


def _find_pairing_protocols(conf):
    available = {svc.protocol for svc in conf.services if svc.protocol is not None}
    return [p for p in _PAIRING_ORDER if p in available]


async def _begin_pairing(protocol):
    global _pairing
    storage = await _load_storage()
    pairing = await pyatv.pair(_pairing_conf, protocol, _loop, storage=storage)
    await pairing.begin()
    _pairing = pairing


def start_pairing(identifier):
    global _pairing, _pairing_queue, _pairing_conf
    try:
        conf = _last_scan.get(identifier)
        if conf is None:
            return json.dumps(
                {"ok": False, "error": "Device not found — please scan again"}
            )
        protocols = _find_pairing_protocols(conf)
        if not protocols:
            return json.dumps(
                {"ok": False, "error": "This device does not support pairing"}
            )
        _pairing_conf = conf
        _pairing_queue = protocols
        protocol = _pairing_queue.pop(0)
        _submit(_begin_pairing(protocol), timeout=90)
        return json.dumps({"ok": True, "status": "pin_required", "protocol": protocol.name})
    except Exception as exc:
        _cleanup_pairing()
        return json.dumps({"ok": False, "error": str(exc)})


def _cleanup_pairing():
    global _pairing, _pairing_queue, _pairing_conf
    pairing, _pairing = _pairing, None
    _pairing_queue = []
    if pairing is not None:
        try:
            _submit(pairing.close(), timeout=15)
        except Exception:
            pass


def finish_pairing(pin):
    global _pairing
    try:
        if _pairing is None:
            return json.dumps({"ok": False, "error": "No active pairing session"})

        async def _do_finish():
            pairing = _pairing
            pairing.pin(str(pin))
            await pairing.finish()
            await pairing.close()

        _submit(_do_finish(), timeout=90)
        _pairing = None

        if _pairing_queue:
            protocol = _pairing_queue.pop(0)
            try:
                _submit(_begin_pairing(protocol), timeout=90)
                return json.dumps(
                    {"ok": True, "status": "pin_required", "protocol": protocol.name}
                )
            except Exception as exc:
                _cleanup_pairing()
                return json.dumps({"ok": False, "error": str(exc)})

        # Persist credentials now — pyatv does not save storage itself.
        _submit(_save_storage(), timeout=15)
        _emit({"type": "pairing_complete"})
        return json.dumps({"ok": True, "status": "done"})
    except Exception as exc:  # pyatv.exceptions.PairingError and friends
        _cleanup_pairing()
        return json.dumps({"ok": False, "error": str(exc)})


def cancel_pairing():
    _cleanup_pairing()
    return json.dumps({"ok": True})


# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

def _settings_identifiers(settings):
    """All identifiers (MACs/UUIDs) a storage Settings object knows about."""
    ids = []
    protocols = getattr(settings, "protocols", None)
    if protocols is not None:
        for proto in ("airplay", "companion", "dmap", "mrp", "raop"):
            svc = getattr(protocols, proto, None)
            value = getattr(svc, "identifier", None) if svc is not None else None
            if value:
                ids.append(str(value))
    info = getattr(settings, "info", None)
    if info is not None:
        mac = getattr(info, "mac", None)
        if mac:
            ids.append(str(mac))
    return ids


def _settings_has_credentials(settings):
    protocols = getattr(settings, "protocols", None)
    if protocols is None:
        return False
    for proto in ("airplay", "companion"):
        svc = getattr(protocols, proto, None)
        if svc is not None and getattr(svc, "credentials", None):
            return True
    return False


def _identifiers_for(identifier):
    """Resolve an identifier (usually an IP from a scan) to the full set of
    identifiers for that device, using the most recent scan results."""
    conf = _last_scan.get(identifier)
    if conf is None:
        return {identifier}, None
    return {str(i) for i in conf.all_identifiers}, conf.name


async def _has_credentials_async(identifier):
    storage = await _load_storage()
    idents, name = _identifiers_for(identifier)
    for settings in storage.settings:
        if name and getattr(getattr(settings, "info", None), "name", None) == name:
            return _settings_has_credentials(settings)
        if idents.intersection(_settings_identifiers(settings)):
            return _settings_has_credentials(settings)
    return False


def has_credentials(identifier):
    try:
        paired = _submit(_has_credentials_async(identifier), timeout=20)
        return json.dumps({"ok": True, "paired": bool(paired)})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


async def _remove_credentials_async(identifier):
    storage = await _load_storage()
    idents, name = _identifiers_for(identifier)
    removed = False
    for settings in list(storage.settings):
        name_match = name and getattr(
            getattr(settings, "info", None), "name", None
        ) == name
        id_match = bool(idents.intersection(_settings_identifiers(settings)))
        if name_match or id_match:
            await storage.remove_settings(settings)
            removed = True
    if removed:
        await storage.save()
    return removed


def remove_credentials(identifier):
    try:
        removed = _submit(_remove_credentials_async(identifier), timeout=20)
        return json.dumps({"ok": True, "removed": bool(removed)})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


# ---------------------------------------------------------------------------
# Connection lifecycle with automatic reconnect
# ---------------------------------------------------------------------------

_atv = None
_connected_identifier = None
_connected_name = None
_connected_conf = None
_auto_reconnect = False
_session = 0  # bumped on disconnect to invalidate in-flight connects
_power_state = None  # None = unknown, otherwise PowerState name (On/Off/Idle)


class _PowerListener:
    """Receives power state updates from the Apple TV (when supported)."""

    def powerstate_update(self, old_state, new_state):
        global _power_state
        _power_state = getattr(new_state, "name", str(new_state))
        _emit({"type": "power_state", "state": _power_state})


def _refresh_power_state():
    global _power_state
    try:
        state = _atv.power.power_state
        _power_state = getattr(state, "name", str(state))
    except Exception:
        if _power_state is None:
            _power_state = None  # keep unknown


class _DeviceListener:
    """pyatv device listener — called on the event loop when the link drops.

    Only reacts while this is still the ACTIVE connection: deliberately
    closing a superseded link also fires connection_lost, and acting on
    those causes reconnect storms (multiple competing reconnect loops)."""

    def __init__(self, atv):
        self.atv = atv

    def connection_lost(self, exception):
        if _atv is not self.atv:
            return  # stale link we already replaced or closed — ignore
        _emit({"type": "connection_lost", "error": str(exception)})

    def connection_closed(self):
        pass


async def _find_config(identifier):
    # A connectable config needs live service info (ports etc.), which only a
    # scan provides; storage settings alone cannot be connected to.
    conf = _last_scan.get(identifier)
    if conf is not None:
        return conf
    return None


async def _connect_async(identifier):
    global _atv, _connected_identifier, _connected_name, _auto_reconnect
    session = _session
    conf = await _find_config(identifier)
    if conf is None:
        raise RuntimeError("No device found for identifier: %s" % identifier)

    # Establish the new link FIRST and only then drop the old one — this
    # avoids a window where _atv is None and every command fails with
    # "Not connected" (the source of the stuck error message).
    storage = _get_storage()
    atv = await pyatv.connect(conf, _loop, storage=storage)
    if session != _session:
        # The user disconnected while we were connecting — drop this link.
        try:
            await atv.close()
        except Exception:
            pass
        raise RuntimeError("stale session")
    try:
        atv.listener = _DeviceListener(atv)
    except Exception:
        pass  # listener is best-effort
    try:
        atv.power.listener = _PowerListener()
    except Exception:
        pass

    old = _atv
    _atv = atv
    if old is not None and old is not atv:
        # Detach the listener so this deliberate close doesn't fire a stale
        # connection_lost event.
        try:
            old.listener = None
        except Exception:
            pass
        try:
            await old.close()
        except Exception:
            pass
    _refresh_power_state()
    _connected_identifier = identifier
    _connected_name = conf.name
    _connected_conf = conf
    _auto_reconnect = True
    return {"name": conf.name, "identifier": identifier}


async def _tcp_probe():
    """Liveness check: can we still open a TCP connection to the Apple TV's
    Companion port? (metadata/power requests are unreliable on newer tvOS,
    but reachability is what actually matters here.)"""
    conf = _connected_conf
    if conf is None:
        return False
    try:
        host = str(conf.address)
        service = None
        try:
            service = conf.get_service(Protocol.Companion)
        except Exception:
            service = None
        if service is None:
            for svc in conf.services:
                if getattr(svc, "port", 0):
                    service = svc
                    break
        port = int(getattr(service, "port", 0) or 49152)
        await asyncio.wait_for(
            _loop.run_in_executor(None, _tcp_connect, host, port), timeout=5
        )
        return True
    except Exception:
        return False


def _tcp_connect(host, port):
    import socket

    sock = socket.create_connection((host, port), timeout=4)
    sock.close()


def connect_device(identifier):
    try:
        info = _submit(_connect_async(identifier), timeout=45)
        _emit({"type": "connected", "device": info})
        return json.dumps({"ok": True, **info})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


def disconnect():
    global _atv, _connected_identifier, _connected_name, _auto_reconnect
    global _session, _connected_conf
    _auto_reconnect = False
    _session += 1
    _connected_conf = None
    identifier, _connected_identifier = _connected_identifier, None
    name, _connected_name = _connected_name, None

    async def _close():
        atv = _atv
        if atv is not None:
            try:
                atv.listener = None
            except Exception:
                pass
            await atv.close()

    try:
        _submit(_close(), timeout=15)
    except Exception:
        pass
    _atv = None
    _emit({"type": "disconnected", "identifier": identifier, "name": name})
    return json.dumps({"ok": True})


def get_state():
    return json.dumps(
        {
            "ok": True,
            "connected": _atv is not None,
            "device": _connected_name,
            "identifier": _connected_identifier,
            "autoReconnect": _auto_reconnect,
            "powerState": _power_state,
        }
    )


def shutdown():
    try:
        disconnect()
    except Exception:
        pass
    return True


# ---------------------------------------------------------------------------
# Remote commands & keyboard input
# ---------------------------------------------------------------------------

_SIMPLE_COMMANDS = {
    "up": lambda atv: atv.remote_control.up(),
    "down": lambda atv: atv.remote_control.down(),
    "left": lambda atv: atv.remote_control.left(),
    "right": lambda atv: atv.remote_control.right(),
    "select": lambda atv: atv.remote_control.select(),
    "menu": lambda atv: atv.remote_control.menu(),
    "home": lambda atv: atv.remote_control.home(),
    "top_menu": lambda atv: atv.remote_control.top_menu(),
    "play": lambda atv: atv.remote_control.play(),
    "pause": lambda atv: atv.remote_control.pause(),
    "play_pause": lambda atv: atv.remote_control.play_pause(),
    "next": lambda atv: atv.remote_control.next(),
    "previous": lambda atv: atv.remote_control.previous(),
    "skip_forward": lambda atv: atv.remote_control.skip_forward(),
    "skip_backward": lambda atv: atv.remote_control.skip_backward(),
    "volume_up": lambda atv: atv.audio.volume_up(),
    "volume_down": lambda atv: atv.audio.volume_down(),
}


async def _send_command_async(cmd):
    global _power_state
    atv = _atv
    if atv is None:
        raise RuntimeError("Not connected to an Apple TV")

    action = _SIMPLE_COMMANDS.get(cmd)
    if action is not None:
        await action(atv)
    elif cmd == "mute":
        await atv.audio.set_volume(0.0)
    elif cmd == "power_on":
        try:
            await atv.power.turn_on()
        except Exception:
            try:
                await atv.remote_control.wakeup()
            except Exception:
                pass
        # Wake-on-LAN as a last resort: the Apple TV keeps its network stack
        # alive in sleep and responds to magic packets even when the protocol
        # level wake commands are not supported.
        try:
            await _wake_on_lan()
        except Exception:
            pass
        _power_state = "On"
    elif cmd == "power_off":
        try:
            await atv.power.turn_off()
        except Exception:
            await atv.remote_control.suspend()
        _power_state = "Off"
    else:
        raise RuntimeError("Unknown command: %s" % cmd)


async def _wake_on_lan():
    """Send a Wake-on-LAN magic packet to the Apple TV.

    The Apple TV keeps its network interface alive while asleep, so a magic
    packet wakes it even when protocol-level wake commands are unavailable.
    The MAC comes from the discovered config identifiers, falling back to the
    kernel ARP table.
    """
    import socket

    identifier = _connected_identifier
    mac = None
    conf = _last_scan.get(identifier)
    if conf is None:
        conf = await _find_config(identifier)
    if conf is not None:
        for cand in conf.all_identifiers:
            text = str(cand)
            if ":" in text and len(text) == 17:
                mac = text
                break
    if mac is None:
        mac = _mac_from_arp(identifier)
    if mac is None:
        raise RuntimeError("Could not determine MAC address for Wake-on-LAN")

    payload = bytes.fromhex(mac.replace(":", "").replace("-", ""))
    magic = b"\xff" * 6 + payload * 16

    targets = ["255.255.255.255"]
    directed = _directed_broadcast()
    if directed:
        targets.append(directed)

    for target in targets:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.sendto(magic, (target, 9))
            sock.close()
        except Exception:
            pass


def _mac_from_arp(ip):
    try:
        with open("/proc/net/arp") as fh:
            for line in fh.readlines()[1:]:
                parts = line.split()
                if parts and parts[0] == ip and parts[3] != "00:00:00:00:00:00":
                    return parts[3]
    except Exception:
        pass
    return None


def _directed_broadcast():
    try:
        import socket

        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect((_connected_identifier or "8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ".".join(ip.split(".")[:3]) + ".255"
    except Exception:
        return None


def send_command(cmd):
    cmd = str(cmd)
    try:
        _submit(_send_command_async(cmd), timeout=20)
        return json.dumps({"ok": True})
    except Exception as exc:
        identifier = _connected_identifier
        if identifier is None:
            return json.dumps({"ok": False, "error": str(exc)})
        # The link likely died silently while the app was backgrounded
        # (Android freezes the process; no connection_lost is ever raised).
        # Reconnect once and retry the command.
        try:
            info = _submit(_connect_async(identifier), timeout=15)
            _emit({"type": "connected", "device": info})
            _submit(_send_command_async(cmd), timeout=20)
            return json.dumps({"ok": True, "reconnected": True})
        except Exception:
            _emit(
                {
                    "type": "reconnecting",
                    "device": _connected_name,
                    "error": str(exc),
                }
            )
            return json.dumps({"ok": False, "error": str(exc)})


def on_foreground():
    """App resumed: probe the connection and revive it if the socket died
    while the process was frozen in the background."""
    try:
        if _atv is None or _connected_identifier is None:
            return json.dumps({"ok": True, "connected": False})

        if _submit(_tcp_probe(), timeout=8):
            return json.dumps({"ok": True, "connected": True})

        info = _submit(_connect_async(_connected_identifier), timeout=15)
        _emit({"type": "connected", "device": info})
        return json.dumps({"ok": True, "connected": True, "reconnected": True})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


async def _send_text_async(text):
    atv = _atv
    if atv is None:
        raise RuntimeError("Not connected to an Apple TV")
    await atv.keyboard.text_set(str(text))


def send_text(text):
    try:
        _submit(_send_text_async(text), timeout=20)
        return json.dumps({"ok": True})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


# ---------------------------------------------------------------------------
# Installed apps: list + launch (Companion protocol via pyatv's Apps interface)
# ---------------------------------------------------------------------------

async def _list_apps_async():
    atv = _atv
    if atv is None:
        raise RuntimeError("Not connected to an Apple TV")
    apps = await atv.apps.app_list()
    return [
        {"name": a.name or a.bundle_id, "bundleId": a.bundle_id}
        for a in apps
    ]


def list_apps():
    try:
        apps = _submit(_list_apps_async(), timeout=25)
        return json.dumps({"ok": True, "apps": apps})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})


async def _launch_app_async(bundle_id):
    atv = _atv
    if atv is None:
        raise RuntimeError("Not connected to an Apple TV")
    await atv.apps.launch_app(str(bundle_id))


def launch_app(bundle_id):
    try:
        _submit(_launch_app_async(bundle_id), timeout=20)
        return json.dumps({"ok": True})
    except Exception as exc:
        return json.dumps({"ok": False, "error": str(exc)})
