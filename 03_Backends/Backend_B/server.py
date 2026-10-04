from http.server import BaseHTTPRequestHandler, HTTPServer
import json


class BackendBHandler(BaseHTTPRequestHandler):

    def send_response_with_backend(self, status_code, body, send_body=True):
        response = json.dumps(body).encode()

        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Backend", "B")
        self.send_header("Cache-Control", "max-age=60")
        self.send_header("ETag", '"teamabs-v1"')
        self.end_headers()

        if send_body:
            self.wfile.write(response)

    def handle_request(self, send_body=True):

        if self.path == "/":
            body = {
                "backend": "B",
                "message": "Response from Backend B",
                "server": "Mac 3",
                "port": 3002
            }

        elif self.path == "/api/status":
            body = {
                "backend": "B",
                "status": "healthy",
                "server": "Mac 3",
                "port": 3002
            }

        else:
            self.send_response_with_backend(
                404,
                {
                    "error": "Not Found",
                    "backend": "B"
                },
                send_body
            )
            return

        etag = '"teamabs-v1"'

        if self.headers.get("If-None-Match") == etag:
            self.send_response(304)
            self.send_header("ETag", etag)
            self.send_header("Cache-Control", "max-age=60")
            self.end_headers()
            return

        self.send_response_with_backend(200, body, send_body)

    def do_GET(self):
        self.handle_request(send_body=True)

    def do_HEAD(self):
        self.handle_request(send_body=False)

    def log_message(self, format, *args):
        print(f"[Backend B] {self.address_string()} - {format % args}")


server = HTTPServer(("0.0.0.0", 3002), BackendBHandler)

print("Backend B running on 0.0.0.0:3002")

server.serve_forever()
