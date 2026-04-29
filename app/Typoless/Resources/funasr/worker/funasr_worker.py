#!/usr/bin/env python3
"""FunASR sidecar worker for Typoless.

Communicates with the Swift host via stdio JSON-RPC 2.0.
Reads one JSON request per line from stdin, writes one JSON response per line to stdout.
All logging and diagnostics go to stderr only.
"""

import json
import logging
import os
import sys
import time
import traceback
from typing import Optional
from pathlib import Path

import soundfile as sf

# Redirect warnings and third-party output to stderr before any imports
# that might pollute stdout
sys.stdout = open(sys.stdout.fileno(), mode="w", buffering=1, encoding="utf-8")
_real_stdout = sys.stdout
sys.stderr = open(sys.stderr.fileno(), mode="w", buffering=1, encoding="utf-8")

# Capture any stray stdout from imports
_rpc_stdout = os.fdopen(os.dup(sys.stdout.fileno()), mode="w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="[funasr-worker] %(levelname)s %(message)s",
)
logger = logging.getLogger("funasr-worker")

# ---------------------------------------------------------------------------
# JSON-RPC 2.0 helpers
# ---------------------------------------------------------------------------

JSONRPC_PARSE_ERROR = -32700
JSONRPC_INVALID_REQUEST = -32600
JSONRPC_METHOD_NOT_FOUND = -32601
JSONRPC_INVALID_PARAMS = -32602
JSONRPC_INTERNAL_ERROR = -32603
JSONRPC_APP_ERROR = -1


def _ok(result: dict, req_id):
    return {"jsonrpc": "2.0", "result": result, "id": req_id}


def _err(code: int, message: str, req_id=None):
    return {"jsonrpc": "2.0", "error": {"code": code, "message": message}, "id": req_id}


def _write(obj: dict):
    """Write a single compact JSON line to stdout and flush."""
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    _rpc_stdout.write(line + "\n")
    _rpc_stdout.flush()


# ---------------------------------------------------------------------------
# Model manager
# ---------------------------------------------------------------------------

class ModelManager:
    """Lazy-loading FunASR model with MPS→CPU fallback."""

    def __init__(self, resource_root: Path):
        self.resource_root = resource_root
        self.model = None
        self.device = None
        self._loaded = False

    def _resolve_model_paths(self) -> dict:
        """Resolve model directories from manifest or default convention."""
        manifest_path = self.resource_root / "manifest.json"
        if manifest_path.exists():
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
            models_cfg = manifest.get("models", {})
            paths = {}
            for key in ("asr", "vad"):
                entry = models_cfg.get(key, {})
                required = entry.get("required", key in ("asr", "vad"))
                if not entry and not required:
                    continue
                rel = entry.get("path", f"models/{entry.get('name', key)}")
                full = self.resource_root / rel
                if not full.exists():
                    if not required:
                        continue
                    raise FileNotFoundError(f"Model directory missing: {full}")
                paths[key] = str(full)
            return paths

        # Fallback: conventional directory names
        defaults = {
            "asr": self.resource_root / "models" / "paraformer-zh",
            "vad": self.resource_root / "models" / "fsmn-vad",
        }
        for key, p in defaults.items():
            if not p.exists():
                raise FileNotFoundError(f"Model directory missing: {p}")

        paths = {k: str(v) for k, v in defaults.items()}
        return paths

    def _select_device(self) -> str:
        """Select best available device: MPS > CPU."""
        try:
            import torch
            if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                return "mps"
        except Exception:
            pass
        return "cpu"

    def load(self):
        """Load models. Tries MPS first, falls back to CPU on failure."""
        if self._loaded:
            return

        paths = self._resolve_model_paths()
        device = self._select_device()

        from funasr import AutoModel  # noqa: late import

        for attempt_device in ([device, "cpu"] if device != "cpu" else ["cpu"]):
            try:
                logger.info("Loading FunASR models on device=%s ...", attempt_device)
                kwargs = dict(
                    model=paths["asr"],
                    vad_model=paths["vad"],
                    device=attempt_device,
                    disable_update=True,
                    log_level="ERROR",
                )

                self.model = AutoModel(**kwargs)
                self.device = attempt_device
                self._loaded = True
                logger.info("Models loaded successfully on device=%s", attempt_device)
                return
            except Exception:
                logger.warning(
                    "Failed to load on device=%s, %s",
                    attempt_device,
                    "retrying on CPU..." if attempt_device != "cpu" else "giving up.",
                )
                if attempt_device == "cpu":
                    raise

    def recognize(self, wav_path: str, hotwords: str = "") -> dict:
        """Run recognition on a WAV file. Returns {"text": ..., "duration_ms": ...}."""
        if not self._loaded:
            self.load()

        p = Path(wav_path)
        if not p.exists():
            raise FileNotFoundError(f"WAV file not found: {wav_path}")
        if not p.is_file():
            raise ValueError(f"WAV path is not a file: {wav_path}")
        if p.stat().st_size == 0:
            raise ValueError(f"WAV file is empty: {wav_path}")

        speech, sample_rate = sf.read(wav_path, dtype="float32")
        if getattr(speech, "ndim", 1) > 1:
            speech = speech.mean(axis=1)

        t0 = time.monotonic()
        kwargs = {
            "input": speech,
            "fs": int(sample_rate),
        }
        if hotwords:
            kwargs["hotword"] = hotwords
        result = self.model.generate(**kwargs)
        duration_ms = int((time.monotonic() - t0) * 1000)

        text = ""
        if result and len(result) > 0:
            item = result[0]
            if isinstance(item, dict):
                text = item.get("text", "")
            elif isinstance(item, str):
                text = item

        return {"text": text, "duration_ms": duration_ms}


# ---------------------------------------------------------------------------
# Request handlers
# ---------------------------------------------------------------------------

_manager: Optional[ModelManager] = None


def _get_manager() -> ModelManager:
    global _manager
    if _manager is None:
        resource_root = Path(os.environ.get(
            "FUNASR_RESOURCE_PATH",
            str(Path(__file__).resolve().parent.parent),
        ))
        _manager = ModelManager(resource_root)
    return _manager


def handle_ping(params: dict, req_id) -> dict:
    return _ok({"status": "ok"}, req_id)


def handle_warmup(params: dict, req_id) -> dict:
    mgr = _get_manager()
    mgr.load()
    return _ok({"status": "ok", "device": mgr.device}, req_id)


def handle_recognize(params: dict, req_id) -> dict:
    wav_path = params.get("wav_path")
    if not wav_path:
        return _err(JSONRPC_INVALID_PARAMS, "missing required param: wav_path", req_id)

    hotwords = params.get("hotwords", "")
    if not isinstance(hotwords, str):
        return _err(JSONRPC_INVALID_PARAMS, "hotwords must be a string", req_id)

    mgr = _get_manager()
    result = mgr.recognize(wav_path, hotwords)
    return _ok(result, req_id)


METHODS = {
    "ping": handle_ping,
    "warmup": handle_warmup,
    "recognize": handle_recognize,
}


# ---------------------------------------------------------------------------
# Main event loop
# ---------------------------------------------------------------------------

def dispatch(line: str):
    """Parse and dispatch one JSON-RPC request."""
    try:
        req = json.loads(line)
    except json.JSONDecodeError as e:
        _write(_err(JSONRPC_PARSE_ERROR, f"JSON parse error: {e}"))
        return

    req_id = req.get("id")

    if not isinstance(req, dict) or req.get("jsonrpc") != "2.0":
        _write(_err(JSONRPC_INVALID_REQUEST, "invalid JSON-RPC 2.0 request", req_id))
        return

    method = req.get("method")
    if not method or method not in METHODS:
        _write(_err(JSONRPC_METHOD_NOT_FOUND, f"unknown method: {method}", req_id))
        return

    params = req.get("params", {})
    if not isinstance(params, dict):
        _write(_err(JSONRPC_INVALID_PARAMS, "params must be an object", req_id))
        return

    try:
        response = METHODS[method](params, req_id)
        _write(response)
    except FileNotFoundError as e:
        _write(_err(JSONRPC_APP_ERROR, str(e), req_id))
    except Exception as e:
        logger.error("Handler error: %s\n%s", e, traceback.format_exc())
        _write(_err(JSONRPC_INTERNAL_ERROR, str(e), req_id))


def main():
    logger.info("FunASR worker started (pid=%d)", os.getpid())

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            dispatch(line)
    except KeyboardInterrupt:
        pass
    except EOFError:
        pass

    logger.info("FunASR worker exiting")


if __name__ == "__main__":
    main()
