#!/usr/bin/env python3
import socket
import sys
import threading


def pump_stdin_to_socket(sock: socket.socket) -> None:
    try:
        while True:
            chunk = sys.stdin.buffer.read(65536)
            if not chunk:
                try:
                    sock.shutdown(socket.SHUT_WR)
                except OSError:
                    pass
                break
            sock.sendall(chunk)
    except (BrokenPipeError, OSError):
        pass


def pump_socket_to_stdout(sock: socket.socket) -> None:
    try:
        while True:
            chunk = sock.recv(65536)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
    except OSError:
        pass


def main() -> int:
    host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 6005

    with socket.create_connection((host, port)) as sock:
        writer = threading.Thread(target=pump_stdin_to_socket, args=(sock,), daemon=True)
        writer.start()
        pump_socket_to_stdout(sock)
        writer.join(timeout=0.1)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
