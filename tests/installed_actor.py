"""Installed actor with disposable actual CouchDB and StarRouter (loopback only)."""
import base64
import json
import os
from pathlib import Path
import secrets
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import zmq


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def eventually(action, description, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            result = action()
            if result:
                return result
        except (HTTPError, URLError, ConnectionError):
            pass
        time.sleep(0.1)
    raise AssertionError(description)


actor_bin, broker_bin, couch_root = [str(Path(p).resolve()) for p in sys.argv[1:]]
processes = []
context = zmq.Context()
api = None
with tempfile.TemporaryDirectory(prefix="database-actor-") as directory:
    work = Path(directory)
    user, password = "fixture", secrets.token_hex(24)
    secret = work / "password"
    secret.write_text(password)
    secret.chmod(0o600)
    db_port, api_port, pub_port = port(), port(), port()
    base = f"http://127.0.0.1:{db_port}"
    authorization = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    def request(path, method="GET", data=None):
        payload = None if data is None else json.dumps(data).encode()
        req = Request(base + path, data=payload, method=method,
                      headers={"Authorization": authorization, "Content-Type": "application/json"})
        with urlopen(req, timeout=3) as response:
            return json.load(response)

    def start(name, argv, env):
        log = open(work / f"{name}.log", "w+")
        process = subprocess.Popen(argv, cwd=work, env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        processes.append((process, log))
        return process

    try:
        config = work / "local.ini"
        config.write_text(f"""[couchdb]
database_dir = {work}/data
view_index_dir = {work}/view
uri_file = {work}/couch.uri
single_node = true
[chttpd]
bind_address = 127.0.0.1
port = {db_port}
[httpd]
bind_address = 127.0.0.1
port = {port()}
[cluster]
n = 1
[log]
writer = stderr
level = error
[replicator]
ssl_trusted_certificates_file = {os.environ['SSL_CERT_FILE']}
[admins]
{user} = {password}
""")
        config.chmod(0o600)
        args_file = work / "vm.args"
        # Retain producer defaults, including -noinput and loopback distribution.
        default_args = (Path(couch_root) / "etc/vm.args").read_text().splitlines()
        args_lines = [line for line in default_args if not line.lstrip().startswith(
            ("-name ", "-setcookie ", "+S ", "+A "))]
        args_file.write_text("\n".join(args_lines) +
                             f"\n-name fixture_{secrets.token_hex(4)}@127.0.0.1\n"
                             f"-setcookie {secrets.token_hex(24)}\n+S 2:2\n+A 4\n")
        args_file.chmod(0o600)
        # OTP needs an explicit trust store inside the Nix sandbox:
        # https://www.erlang.org/doc/apps/public_key/public_key.html#cacerts_load/0
        ca_argument = shlex.quote(json.dumps(os.environ["SSL_CERT_FILE"]))
        couch_env = {**os.environ, "HOME": str(work), "COUCHDB_ARGS_FILE": str(args_file),
                     "ERL_FLAGS": (f"-couch_ini {couch_root}/etc/default.ini {config} "
                                   f"-public_key cacerts_path {ca_argument}")}
        couch = start("couch", [couch_root + "/bin/couchdb"], couch_env)
        def couch_ready():
            assert couch.poll() is None, "CouchDB exited during startup"
            return request("/_up").get("status") == "ok"
        eventually(couch_ready, "CouchDB readiness", 60)
        for database in ("_users", "_replicator", "_global_changes", "actor_fixture"):
            try:
                assert request("/" + database, "PUT")["ok"]
            except HTTPError as error:
                if error.code != 412:  # Single-node setup may already create system DBs.
                    raise

        api_address = f"tcp://127.0.0.1:{api_port}"
        pub_address = f"tcp://127.0.0.1:{pub_port}"
        broker = start("broker", [broker_bin, "--apiAddress=" + api_address,
                                   "--pubAddress=" + pub_address], os.environ.copy())
        api = context.socket(zmq.DEALER)
        api.setsockopt(zmq.IDENTITY, b"packaging-fixture")
        api.setsockopt(zmq.RCVTIMEO, 10000)
        api.setsockopt(zmq.SNDTIMEO, 10000)
        api.connect(api_address)

        def send(event, value, topic=b"document"):
            api.send_multipart([b"", b"SC01", b"packaging-fixture", b"fixture:message",
                                str(int(time.time())).encode(), str(event).encode(),
                                topic, json.dumps(value).encode()])
            return api.recv_multipart()

        assert send(7, "", b"fixture") == [b"1"]
        actor_env = {**os.environ, "DB_USER": user, "DB_PASS_FILE": str(secret),
                     "DB_HOST": "http://127.0.0.1", "DB_PORT": str(db_port),
                     "DB_NAME": "actor_fixture", "ROUTER_API_ADDRESS": api_address,
                     "ROUTER_PUB_ADDRESS": pub_address, "COUCHDB_LOG": str(work / "actor-private.log")}
        actor_env.pop("DB_PASS", None)
        actor_env.pop("LD_LIBRARY_PATH", None)
        subprocess.run([actor_bin, "--help"], cwd=work, env=actor_env,
                       check=True, timeout=15, stdout=subprocess.DEVNULL)
        actor = start("actor", [actor_bin], actor_env)
        eventually(lambda: "DatabaseActor connected to StarRouter" in
                   (work / "actor.log").read_text(), "actor broker registration")
        time.sleep(0.3)  # Allow the actual PUB/SUB subscription handshake.
        document = {"id": "document:fixture", "dataset": "fixture", "dtype": "document",
                    "schemaVersion": "0.10.1", "deleted": False,
                    "extensions": {"opaque": None, "items": []}}
        assert send(3, document) == [b"1"]
        stored = eventually(lambda: request("/actor_fixture/document:fixture"), "accepted write")
        for key, value in document.items():
            assert stored[key] == value, (key, stored)
        assert stored["_id"] == document["id"] and "_rev" in stored

        invalid = {**document, "id": "document:invalid", "schemaVersion": "0.10.2"}
        assert send(3, invalid) == [b"2"]
        time.sleep(0.3)
        assert request("/actor_fixture/_all_docs")["total_rows"] == 1
        assert actor.poll() is None and broker.poll() is None and couch.poll() is None

        # The fixture terminates long-running services; no graceful-drain claim.
        actor.terminate()
        actor.wait(timeout=5)
        wrong = work / "wrong-password"
        wrong.write_text(secrets.token_hex(24))
        wrong.chmod(0o600)
        failed = start("invalid-login", [actor_bin], {**actor_env, "DB_PASS_FILE": str(wrong)})
        assert failed.wait(timeout=15) != 0
        assert "DatabaseActor connected" not in (work / "invalid-login.log").read_text()
        print("installed CouchDB/StarRouter write, readback, malformed NACK, secret-file startup, termination and rejected-login PASS")
    finally:
        if api is not None:
            api.close(linger=0)
        context.term()
        for process, log in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            if sys.exc_info()[0] is not None:
                log.seek(0)
                print(log.read()[-4000:], file=sys.stderr)
            log.close()
