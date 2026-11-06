#!/usr/bin/env python3
import http.server, re, sys, time

path = sys.argv[1]
port_file = sys.argv[2]
slow_default = len(sys.argv) > 3 and sys.argv[3] == 'slow'
data = open(path, 'rb').read()

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_): pass
    def _serve(self, head=False):
        slow = slow_default or 'slow=1' in self.path
        range_header = self.headers.get('Range')
        start, end, status = 0, len(data) - 1, 200
        if range_header:
            m = re.match(r'bytes=(\d+)-(\d*)', range_header)
            if m:
                start = int(m.group(1))
                if m.group(2): end = min(int(m.group(2)), len(data) - 1)
                if start >= len(data):
                    self.send_response(416); self.send_header('Content-Length', '0'); self.end_headers(); return
                status = 206
        body = data[start:end + 1]
        self.send_response(status)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Type', 'application/octet-stream')
        self.send_header('Content-Length', str(len(body)))
        if status == 206:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, len(data)))
        self.end_headers()
        if head: return
        time.sleep(0.5)
        for offset in range(0, len(body), 65536):
            self.wfile.write(body[offset:offset + 65536])
            self.wfile.flush()
            time.sleep(1.0 if slow else 0.05)
    def do_GET(self): self._serve(False)
    def do_HEAD(self): self._serve(True)

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(port_file, 'w') as f: f.write(str(server.server_address[1]))
server.serve_forever()
