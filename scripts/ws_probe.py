#!/usr/bin/env python3
"""Prove a running relay speaks the Plezy relay protocol.

Connects to /relay, creates a room at protocolVersion 2, and asserts the server
answers with `created` advertising the `authenticatedResume` feature -- the
capability upstream's README requires self-hosted relays to support.

Usage: ws_probe.py [port]   (default 8080)
"""
import base64
import json
import os
import socket
import struct
import sys

PROTOCOL_VERSION = 2
RECONNECT_TOKEN_BYTES = 32
REQUIRED_FEATURE = "authenticatedResume"


def encode_frame(payload: bytes) -> bytes:
    mask = os.urandom(4)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    n = len(payload)
    if n < 126:
        header = struct.pack("!BB", 0x81, 0x80 | n)
    elif n < (1 << 16):
        header = struct.pack("!BBH", 0x81, 0x80 | 126, n)
    else:
        header = struct.pack("!BBQ", 0x81, 0x80 | 127, n)
    return header + mask + masked


def read_frame(sock: socket.socket) -> bytes:
    def exactly(count: int) -> bytes:
        buf = b""
        while len(buf) < count:
            chunk = sock.recv(count - len(buf))
            if not chunk:
                raise EOFError("relay closed the connection")
            buf += chunk
        return buf

    _, second = exactly(2)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", exactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", exactly(8))[0]
    return exactly(length)


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    sock = socket.create_connection(("127.0.0.1", port), timeout=10)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(
        (
            f"GET /relay HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode()
    )

    response = b""
    while b"\r\n\r\n" not in response:
        chunk = sock.recv(4096)
        if not chunk:
            raise EOFError("relay closed during handshake")
        response += chunk
    status = response.split(b"\r\n", 1)[0].decode()
    if "101" not in status:
        print(f"FAIL: expected 101 Switching Protocols, got {status!r}")
        return 1
    print(f"handshake: {status}")

    # protocolVersion 2 rooms must present a caller-minted reconnect token.
    token = base64.urlsafe_b64encode(os.urandom(RECONNECT_TOKEN_BYTES)).decode().rstrip("=")
    sock.sendall(
        encode_frame(
            json.dumps(
                {
                    "type": "create",
                    "sessionId": "ciprobe01",
                    "peerId": "ci-probe-peer",
                    "protocolVersion": PROTOCOL_VERSION,
                    "reconnectToken": token,
                }
            ).encode()
        )
    )

    message = json.loads(read_frame(sock))
    sock.close()

    if message.get("type") != "created":
        print(f"FAIL: expected 'created', got: {json.dumps(message)}")
        return 1
    features = message.get("features", [])
    if REQUIRED_FEATURE not in features:
        print(f"FAIL: {REQUIRED_FEATURE} not advertised; features={features}")
        return 1
    if message.get("protocolVersion") != PROTOCOL_VERSION:
        print(f"FAIL: unexpected protocolVersion {message.get('protocolVersion')}")
        return 1

    print(f"created room, protocolVersion={PROTOCOL_VERSION}, features={features}")
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
