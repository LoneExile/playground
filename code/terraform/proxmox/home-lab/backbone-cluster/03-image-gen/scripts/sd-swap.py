#!/usr/bin/env python3
"""sd-swap — a tiny model-swapping proxy in front of stable-diffusion.cpp's
sd-server. Like llama-swap, but for diffusion.

Presents an Automatic1111-compatible API on SDSWAP_PORT that:
  - lists ALL configured models at /sdapi/v1/sd-models (so Open WebUI shows
    every model in its image-model dropdown), and
  - lazily (re)launches a SINGLE sd-server backend with the requested model
    (the 780M iGPU can only hold one diffusion model at a time), swapping on
    demand and unloading after an idle TTL.

sd-server binds its HTTP port only AFTER the model is fully loaded, so a 200
from the backend's /sdapi/v1/sd-models is a sound readiness signal.

Stdlib only. Config via environment (see sd-swap.env):
  SDSWAP_PORT          listen port                        (default 7860)
  SDSWAP_BACKEND_PORT  internal sd-server port            (default 17860)
  SDSWAP_REGISTRY      models.json path                   (default /opt/sd-cpp/models.json)
  SDSWAP_MODELS_DIR    dir prepended to model filenames   (default /opt/sd-cpp/models)
  SDSWAP_BIN           sd-server binary
  SDSWAP_LIB           LD_LIBRARY_PATH for the backend
  SDSWAP_EXTRA_FLAGS   shared sd-server flags (mitigations)
  SDSWAP_TTL           idle seconds before unload          (default 1800; 0 = never)
  SDSWAP_LOAD_TIMEOUT  seconds to wait for backend health  (default 600)
  SDSWAP_GEN_TIMEOUT   seconds to allow a single txt2img   (default 1800)
"""
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("SDSWAP_PORT", "7860"))
BACKEND_PORT = int(os.environ.get("SDSWAP_BACKEND_PORT", "17860"))
REGISTRY = os.environ.get("SDSWAP_REGISTRY", "/opt/sd-cpp/models.json")
MODELS_DIR = os.environ.get("SDSWAP_MODELS_DIR", "/opt/sd-cpp/models")
BIN = os.environ.get("SDSWAP_BIN", "/opt/sd-cpp/src/build/bin/sd-server")
LIB = os.environ.get("SDSWAP_LIB", os.path.dirname(BIN))
EXTRA = os.environ.get("SDSWAP_EXTRA_FLAGS", "").split()
TTL = int(os.environ.get("SDSWAP_TTL", "1800"))
LOAD_TIMEOUT = int(os.environ.get("SDSWAP_LOAD_TIMEOUT", "600"))
GEN_TIMEOUT = int(os.environ.get("SDSWAP_GEN_TIMEOUT", "1800"))
PROXY_TIMEOUT = 60
BACKEND = "http://127.0.0.1:%d" % BACKEND_PORT
_SKIP_REQ_HEADERS = ("host", "content-length", "connection", "accept-encoding",
                     "transfer-encoding")


def log(*a):
    print("[sd-swap]", *a, flush=True)


try:
    with open(REGISTRY) as _f:
        MODELS = json.load(_f)
    if not isinstance(MODELS, list) or not MODELS:
        raise ValueError("registry must be a non-empty JSON array")
except Exception as _e:  # noqa: BLE001
    print("[sd-swap] FATAL: cannot load registry %s: %s" % (REGISTRY, _e), flush=True)
    sys.exit(1)

BY_TITLE = {m["title"]: m for m in MODELS}
DEFAULT_TITLE = MODELS[0]["title"]

_lock = threading.RLock()
# desired: what the client last asked for; running: what the backend has loaded.
_state = {"desired": DEFAULT_TITLE, "running": None, "proc": None, "last": time.time()}


def _model_path(name):
    return name if os.path.isabs(name) else os.path.join(MODELS_DIR, name)


def _args_for(m):
    a = [BIN, "--listen-ip", "127.0.0.1", "--listen-port", str(BACKEND_PORT)]
    if m["mode"] == "single":
        a += ["--model", _model_path(m["model"])]
    elif m["mode"] == "flux":
        a += [
            "--diffusion-model", _model_path(m["diffusion_model"]),
            "--vae", _model_path(m["vae"]),
            "--clip_l", _model_path(m["clip_l"]),
            "--t5xxl", _model_path(m["t5xxl"]),
        ]
    else:
        raise ValueError("unknown mode: %r" % m.get("mode"))
    return a + EXTRA


def _backend_healthy():
    try:
        urllib.request.urlopen(BACKEND + "/sdapi/v1/sd-models", timeout=3).read()
        return True
    except Exception:
        return False


def _port_free():
    s = socket.socket()
    s.settimeout(0.5)
    try:
        s.connect(("127.0.0.1", BACKEND_PORT))
        return False  # something is listening
    except Exception:
        return True
    finally:
        s.close()


def _wait_port_free(timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _port_free():
            return
        time.sleep(0.5)
    log("warning: backend port %d still busy after %ss" % (BACKEND_PORT, timeout))


def _stop():
    p = _state["proc"]
    if p and p.poll() is None:
        log("stopping backend pid", p.pid, "(", _state["running"], ")")
        try:
            p.terminate()
            try:
                p.wait(timeout=20)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait(timeout=10)
        except Exception as e:
            log("stop error:", e)
    _state["proc"] = None
    _state["running"] = None


def ensure(title=None):
    """Make the backend serve `title` (or the current desired), cold-loading if
    needed. Holds the lock for the whole swap, so generations serialize."""
    with _lock:
        if title is None:
            title = _state["desired"] or DEFAULT_TITLE
        if title not in BY_TITLE:
            log("unknown model %r -> default %r" % (title, DEFAULT_TITLE))
            title = DEFAULT_TITLE
        _state["last"] = time.time()
        if (_state["running"] == title and _state["proc"]
                and _state["proc"].poll() is None and _backend_healthy()):
            return title
        _stop()
        _wait_port_free()
        env = dict(os.environ)
        parts = [LIB] + ([env["LD_LIBRARY_PATH"]] if env.get("LD_LIBRARY_PATH") else [])
        env["LD_LIBRARY_PATH"] = ":".join(parts)
        log("launching backend:", title, "(", BY_TITLE[title]["mode"], ")")
        _state["proc"] = subprocess.Popen(_args_for(BY_TITLE[title]), env=env)
        _state["running"] = title
        deadline = time.time() + LOAD_TIMEOUT
        while time.time() < deadline:
            if _state["proc"].poll() is not None:
                rc = _state["proc"].returncode
                _state["proc"] = None
                _state["running"] = None
                raise RuntimeError("backend for %s exited during load (rc=%s)" % (title, rc))
            if _backend_healthy():
                log("backend ready:", title)
                _state["last"] = time.time()
                return title
            time.sleep(1)
        raise RuntimeError("backend load timeout (%ss) for %s" % (LOAD_TIMEOUT, title))


def _ttl_loop():
    if TTL <= 0:
        return
    while True:
        time.sleep(30)
        with _lock:
            if _state["proc"] and (time.time() - _state["last"] > TTL):
                log("idle %ss > TTL %ss -> unloading"
                    % (int(time.time() - _state["last"]), TTL))
                _stop()


def _sd_models_payload():
    return [
        {"title": m["title"], "model_name": m["title"], "filename": m["title"],
         "hash": None, "sha256": None, "config": None}
        for m in MODELS
    ]


def _proxy(method, path, headers, body, timeout):
    req = urllib.request.Request(BACKEND + path, data=body, method=method)
    for k, v in headers.items():
        if k.lower() in _SKIP_REQ_HEADERS:
            continue
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), r.headers.get_content_type() or "application/json"
    except urllib.error.HTTPError as e:
        ct = "application/json"
        try:
            ct = e.headers.get_content_type() or ct
        except Exception:
            pass
        return e.code, e.read(), ct


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def do_GET(self):
        p = self.path.split("?", 1)[0]
        if p == "/sdapi/v1/sd-models":
            return self._send(200, json.dumps(_sd_models_payload()))
        if p == "/sdapi/v1/options":
            with _lock:
                title = _state["desired"] or _state["running"] or DEFAULT_TITLE
            return self._send(200, json.dumps({"sd_model_checkpoint": title}))
        if p in ("/", "/health"):
            return self._send(200, json.dumps(
                {"status": True, "desired": _state["desired"], "running": _state["running"]}))
        try:
            ensure()
            code, body, ct = _proxy("GET", self.path, self.headers, b"", PROXY_TIMEOUT)
        except Exception as e:
            return self._send(502, json.dumps({"error": str(e)}))
        return self._send(code, body, ct)

    def do_POST(self):
        p = self.path.split("?", 1)[0]
        body = self._read_body()
        if p == "/sdapi/v1/options":
            # Record the desired model; the actual (slow) swap happens on txt2img.
            try:
                t = (json.loads(body or b"{}") or {}).get("sd_model_checkpoint")
                if t and t in BY_TITLE:
                    with _lock:
                        _state["desired"] = t
                    log("desired model ->", t)
                elif t:
                    log("ignoring unknown checkpoint:", t)
            except Exception as e:
                log("options parse error:", e)
            return self._send(200, json.dumps({}))
        if p in ("/sdapi/v1/txt2img", "/sdapi/v1/img2img"):
            try:
                ensure()
            except Exception as e:
                return self._send(502, json.dumps({"error": str(e)}))
            code, resp, ct = _proxy("POST", self.path, self.headers, body, GEN_TIMEOUT)
            return self._send(code, resp, ct)
        try:
            ensure()
            code, resp, ct = _proxy("POST", self.path, self.headers, body, PROXY_TIMEOUT)
        except Exception as e:
            return self._send(502, json.dumps({"error": str(e)}))
        return self._send(code, resp, ct)


def main():
    threading.Thread(target=_ttl_loop, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H)
    log("listening on :%d, backend :%d, models=%s, default=%s"
        % (PORT, BACKEND_PORT, list(BY_TITLE), DEFAULT_TITLE))

    def _sig(*_a):
        log("shutdown")
        with _lock:
            _stop()
        srv.shutdown()

    signal.signal(signal.SIGTERM, _sig)
    signal.signal(signal.SIGINT, _sig)
    try:
        srv.serve_forever()
    finally:
        with _lock:
            _stop()


if __name__ == "__main__":
    main()
