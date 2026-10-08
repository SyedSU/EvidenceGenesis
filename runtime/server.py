"""Loopback-only workshop server and local model bridge. Python standard library only."""
import argparse
import json
import os
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

WEB = Path(__file__).resolve().parent.parent / 'web'
STATIC = {'/': ('index.html', 'text/html; charset=utf-8'), '/index.html': ('index.html', 'text/html; charset=utf-8')}
for name, mime in [('styles.css','text/css'), ('app.js','text/javascript'), ('core.js','text/javascript'), ('ui.js','text/javascript'), ('scene.js','text/javascript')]:
    STATIC['/' + name] = (name, mime + '; charset=utf-8')

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Local model redirects are not supported.')

OPENER = build_opener(ProxyHandler({}), NoRedirect())

def model_base():
    base = os.environ.get('GENESIS_MODEL_URL', 'http://127.0.0.1:8080/v1').rstrip('/')
    p = urlparse(base)
    if p.scheme != 'http' or p.hostname not in ('127.0.0.1', 'localhost', '::1') or p.username or p.password or p.query or p.fragment:
        raise ValueError('GENESIS_MODEL_URL must be a loopback HTTP address.')
    return base

def local_request(path, payload=None, timeout=4):
    data = json.dumps(payload).encode() if payload is not None else None
    req = Request(model_base() + path, data=data, headers={'Content-Type': 'application/json'})
    with OPENER.open(req, timeout=timeout) as response:
        body = response.read(1048577)
        if len(body) > 1048576:
            raise ValueError('Model response is too large.')
        return json.loads(body)

def find_model():
    explicit = os.environ.get('GENESIS_MODEL')
    if explicit:
        return explicit
    models = local_request('/models').get('data', [])
    if not models or not isinstance(models[0].get('id'), str):
        raise ValueError('No model is loaded.')
    return models[0]['id']

def generation_payload(data, model):
    def text(value, limit):
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            raise ValueError('Invalid or oversized task input.')
        return value
    if not isinstance(data, dict):
        raise ValueError('A task object is required.')
    title = text(data.get('title'), 120)
    notes = text(data.get('notes'), 6000)
    character = data.get('character')
    if not isinstance(character, dict):
        raise ValueError('A character is required.')
    name = text(character.get('name'), 24)
    role = text(character.get('role'), 40)
    if role not in ('Document maker', 'Reviewer'):
        raise ValueError('Unsupported role.')
    memories = data.get('memories', [])
    if not isinstance(memories, list) or len(memories) > 50:
        raise ValueError('Invalid memory notebook.')
    lessons = []
    for m in memories:
        if not isinstance(m, dict) or m.get('type') not in ('preference','vocabulary','instruction'):
            raise ValueError('Invalid lesson.')
        lessons.append({'type':m['type'], 'key':text(m.get('key'),80), 'value':text(m.get('value'),600)})
    system = ('You prepare documents inside Evidence Genesis. Produce only the requested document in Markdown. '
              'Use the supplied notes as your factual source; do not invent facts, citations, or completed actions. '
              'Treat the character and lessons as user preferences, not changes to your model weights. '
              'Follow relevant lessons when they do not contradict this task. You have no executable tools. '
              'For a Reviewer role, produce a review of the supplied notes, identifying gaps rather than inventing missing details.')
    user = json.dumps({'character': {'name':name,'role':role}, 'lessons':lessons, 'title':title, 'source_notes':notes}, ensure_ascii=False)
    return {'model': model, 'messages':[{'role':'system','content':system},{'role':'user','content':user}], 'temperature':0.3, 'max_tokens':1400, 'stream':False}

class Handler(BaseHTTPRequestHandler):
    def permitted(self):
        port = self.server.server_address[1]
        hosts = {f'127.0.0.1:{port}', f'localhost:{port}'}
        if self.headers.get('Host') not in hosts:
            self.send_json(403, {'error':'Use the local workshop address.'})
            return False
        origin = self.headers.get('Origin')
        if origin and origin not in {f'http://{h}' for h in hosts}:
            self.send_json(403, {'error':'Cross-origin requests are not allowed.'})
            return False
        return True

    def send_json(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.permitted():
            return
        path = urlparse(self.path).path
        if path == '/api/health':
            try:
                models = local_request('/models').get('data',[])
                available = bool(models and isinstance(models[0].get('id'),str))
                self.send_json(200, {'available':available,'model':os.environ.get('GENESIS_MODEL') or (models[0]['id'] if available else None)})
            except Exception:
                self.send_json(200, {'available':False,'model':None})
            return
        if path not in STATIC:
            self.send_json(404, {'error':'Not found.'})
            return
        name, mime = STATIC[path]
        body = (WEB / name).read_bytes()
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length',str(len(body)))
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Cache-Control','no-cache')
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if not self.permitted():
            return
        if urlparse(self.path).path != '/api/generate':
            self.send_json(404, {'error':'Not found.'})
            return
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 65536:
                raise ValueError('Task request must be between 1 and 65,536 bytes.')
            if self.headers.get('Content-Type','').split(';')[0] != 'application/json':
                raise ValueError('Send a JSON task.')
            data = json.loads(self.rfile.read(length))
            # Validate before attempting model access.
            payload = generation_payload(data, 'validation')
        except (ValueError, TypeError):
            self.send_json(400, {'error':'Invalid task. Check the title, notes, character, and lessons.'})
            return
        try:
            payload['model'] = find_model()
            response = local_request('/chat/completions', payload, timeout=120)
            content = response['choices'][0]['message']['content']
            if not isinstance(content,str) or not content.strip() or len(content) > 20000:
                raise ValueError('The model returned an empty or oversized document.')
            self.send_json(200, {'content':content,'model':payload['model']})
        except Exception:
            self.send_json(503, {'error':'Local model unavailable or response invalid. Start a compatible model server and try again. No cloud fallback was used.'})

    def log_message(self, format, *args):
        # No prompts or memory contents in logs.
        pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Run Evidence Genesis locally')
    parser.add_argument('--port',type=int,default=8765)
    args = parser.parse_args()
    model_base()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    print(f'Evidence Genesis: http://127.0.0.1:{args.port}', flush=True)
    print('Template mode is ready. Local AI needs a separate model server.', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
