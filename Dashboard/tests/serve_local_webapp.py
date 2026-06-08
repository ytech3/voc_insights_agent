"""
Tier 3 + Tier 4 helper.

Serves the webapp on http://localhost:8080, rewriting FUNCTION_URL in app.js
to point at the local Azure Function (http://localhost:7071) so the browser
talks to your local `func start` instead of the production Azure Function.

Also serves the Tier 4 iframe wrapper at http://localhost:8080/iframe-test.html.

Usage:
    # In one terminal:
    cd azure_deploy/function
    func start

    # In another terminal:
    python tests/serve_local_webapp.py
    # Then open http://localhost:8080 (Tier 3)
    #         or http://localhost:8080/iframe-test.html (Tier 4)
"""

import http.server
import socketserver
from pathlib import Path

ROOT     = Path(__file__).resolve().parent.parent / "azure_deploy" / "webapp"
TESTS    = Path(__file__).resolve().parent
PORT     = 8080
LOCAL_FUNCTION_URL = "http://localhost:7071"
PROD_FUNCTION_URL  = "https://rays-voc-proxy-dxf8bahjhhbnh4bx.eastus2-01.azurewebsites.net"


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        # Serve the Tier 4 iframe wrapper from tests/ at /iframe-test.html
        if self.path in ("/iframe-test.html", "/iframe-test"):
            data = (TESTS / "tier4_iframe.html").read_bytes()
            self._send_bytes(data, "text/html; charset=utf-8")
            return

        # Rewrite FUNCTION_URL on the fly in app.js
        if self.path.rstrip("/").endswith("/app.js") or self.path == "/app.js":
            content = (ROOT / "app.js").read_text(encoding="utf-8")
            content = content.replace(PROD_FUNCTION_URL, LOCAL_FUNCTION_URL)
            self._send_bytes(content.encode("utf-8"), "text/javascript; charset=utf-8")
            return

        super().do_GET()

    def _send_bytes(self, data: bytes, ctype: str):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    print(f"Serving {ROOT}")
    print(f"  app.js FUNCTION_URL  ->  {LOCAL_FUNCTION_URL}  (rewritten in-flight)")
    print(f"  Tier 3 widget        ->  http://localhost:{PORT}/")
    print(f"  Tier 4 iframe test   ->  http://localhost:{PORT}/iframe-test.html")
    print(f"  Make sure `func start` is running in azure_deploy/function/")
    print(f"  Ctrl+C to stop.")
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
