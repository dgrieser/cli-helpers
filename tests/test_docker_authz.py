import base64
import http.client
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import socket
from tempfile import TemporaryDirectory
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "lib/cli-helpers/etc/cli-helpers/docker-authz"


def load_plugin():
    loader = importlib.machinery.SourceFileLoader("docker_authz", str(PLUGIN))
    spec = importlib.util.spec_from_loader("docker_authz", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


authz = load_plugin()


def request(uri, body=None, method="POST"):
    data = {"RequestMethod": method, "RequestUri": uri}
    if body is not None:
        data["RequestBody"] = base64.b64encode(json.dumps(body).encode()).decode()
    return data


class UnixConnection(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost")
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.path)


class CheckTest(unittest.TestCase):
    def test_allows_plain_container(self):
        self.assertIsNone(authz.check(request("/v1.47/containers/create", {"Image": "alpine", "HostConfig": {}})))

    def test_refuses_privileged_container(self):
        body = {"Image": "podcaster-e2e", "HostConfig": {"Privileged": True}}
        self.assertIn("privileged", authz.check(request("/v1.47/containers/create?name=pe2e", body)))
        self.assertIsNotNone(authz.check(request("/containers/create", body)))

    def test_allows_buildkit_builder(self):
        for image in ("moby/buildkit:buildx-stable-1", "docker.io/moby/buildkit:v0.20.0",
                      "moby/buildkit@sha256:" + "0" * 64, "moby/buildkit"):
            body = {"Image": image, "HostConfig": {"Privileged": True}}
            self.assertIsNone(authz.check(request("/v1.47/containers/create", body)), image)

    def test_refuses_lookalike_of_buildkit(self):
        for image in ("evil/moby/buildkit:latest", "moby/buildkitx:latest", "example.com/moby/buildkit:1"):
            body = {"Image": image, "HostConfig": {"Privileged": True}}
            self.assertIsNotNone(authz.check(request("/v1.47/containers/create", body)), image)

    def test_refuses_create_it_cannot_check(self):
        self.assertIsNotNone(authz.check(request("/v1.47/containers/create")))

    def test_refuses_privileged_exec(self):
        self.assertIsNotNone(authz.check(request("/v1.47/containers/abc/exec", {"Privileged": True, "Cmd": ["sh"]})))
        self.assertIsNone(authz.check(request("/v1.47/containers/abc/exec", {"Cmd": ["sh"]})))

    def test_ignores_other_requests(self):
        self.assertIsNone(authz.check(request("/v1.47/containers/json", method="GET")))
        self.assertIsNone(authz.check(request("/v1.47/containers/abc/start")))


class ServerTest(unittest.TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.path = str(Path(temp.name) / "authz.sock")
        server = authz.Server(self.path, authz.Handler)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        threading.Thread(target=server.serve_forever, daemon=True).start()

    def post(self, path, data):
        connection = UnixConnection(self.path)
        self.addCleanup(connection.close)
        connection.request("POST", path, json.dumps(data), {"Content-Type": "application/json"})
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        return json.loads(response.read())

    def test_protocol(self):
        self.assertEqual(self.post("/Plugin.Activate", {}), {"Implements": ["authz"]})
        body = {"Image": "alpine", "HostConfig": {"Privileged": True}}
        answer = self.post("/AuthZPlugin.AuthZReq", request("/v1.47/containers/create", body))
        self.assertFalse(answer["Allow"])
        self.assertIn("privileged", answer["Msg"])
        answer = self.post("/AuthZPlugin.AuthZReq", request("/v1.47/containers/create", {"Image": "alpine"}))
        self.assertEqual(answer, {"Allow": True})
        self.assertEqual(self.post("/AuthZPlugin.AuthZRes", {}), {"Allow": True})


if __name__ == "__main__":
    unittest.main()
