#!/usr/bin/env python3
"""Send a length-prefixed JSON event to the Claw Island Unix socket."""
import socket, struct, sys, json

SOCK = "/tmp/claw-island.sock"

def send(data: dict):
    payload = json.dumps(data).encode()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(SOCK)
        s.sendall(struct.pack(">I", len(payload)) + payload)
        # For PermissionRequest, wait for response
        if data.get("hook_event_name") == "PermissionRequest":
            hdr = b""
            while len(hdr) < 4:
                hdr += s.recv(4 - len(hdr))
            length = struct.unpack(">I", hdr)[0]
            body = b""
            while len(body) < length:
                body += s.recv(length - len(body))
            print(f"Response: {body.decode()}")
        else:
            # Small delay to let server process
            import time; time.sleep(0.1)

SID = "test-session-001"
TPATH = "/tmp/test-transcript"

match sys.argv[1] if len(sys.argv) > 1 else "":
    case "start":
        send({"hook_event_name": "SessionStart", "session_id": SID, "transcript_path": TPATH, "source": "startup", "model": "test-model"})
        print("Sent SessionStart")
    case "perm":
        send({"hook_event_name": "PermissionRequest", "session_id": SID, "transcript_path": TPATH,
              "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}, "permission_suggestions": None})
        print("Sent PermissionRequest (waiting for response...)")
    case "pret":
        send({"hook_event_name": "PreToolUse", "session_id": SID, "transcript_path": TPATH,
              "tool_name": "Read", "tool_input": {"file_path": "/etc/hosts"}})
        print("Sent PreToolUse")
    case "stop":
        send({"hook_event_name": "Stop", "session_id": SID, "transcript_path": TPATH})
        print("Sent Stop")
    case "end":
        send({"hook_event_name": "SessionEnd", "session_id": SID, "transcript_path": TPATH})
        print("Sent SessionEnd")
    case _:
        print(f"Usage: {sys.argv[0]} <start|perm|pret|stop|end>")
        print("  start  - Create session")
        print("  perm   - Send permission request (blocks until response)")
        print("  pret   - Send PreToolUse (should clear stale approval)")
        print("  stop   - Send Stop")
        print("  end    - Remove session")
