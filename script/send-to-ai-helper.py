#!/usr/bin/env python3
"""Send to AI helper for the SAVY simulator and Mac builds.

SAVY posts {"provider": "Claude" | "ChatGPT", "prompt": "..."} to port 8787 and gets the reply as
plain text. Claude answers through the Claude Code login on this Mac; ChatGPT answers through the
Codex login. No key is copied anywhere. The phone reaches it over Adam's Tailscale network; only
this Mac and Tailscale addresses are answered. Installed as a login item by script/install-helper.sh.
"""
import http.server, ipaddress, json, os, subprocess, sys, tempfile, time

CLAUDE = os.path.expanduser("~/.local/bin/claude")
CODEX = os.path.expanduser("~/.local/bin/codex")
PROVIDERS = {"Claude", "ChatGPT"}


def ask_claude(prompt, env):
    r = subprocess.run([CLAUDE, "-p", "--output-format", "text", prompt],
                       capture_output=True, text=True, env=env, timeout=280)
    out = (r.stdout or "").strip()
    if r.returncode != 0 or not out:
        raise RuntimeError((r.stderr or "no reply").strip()[-600:])
    return out


def ask_chatgpt(prompt, env):
    with tempfile.TemporaryDirectory(prefix="savy-codex-") as work:
        result = os.path.join(work, "answer.txt")
        r = subprocess.run([CODEX, "exec", "--sandbox", "read-only", "--skip-git-repo-check",
                            "--ephemeral", "--output-last-message", result, "-"],
                           input=prompt, capture_output=True, text=True, env=env, cwd=work, timeout=280)
        out = ""
        if os.path.exists(result):
            with open(result, encoding="utf-8") as f:
                out = f.read().strip()
        if r.returncode != 0 or not out:
            raise RuntimeError((r.stderr or r.stdout or "no reply").strip()[-600:])
        return out


TAILNET = ipaddress.ip_network("100.64.0.0/10")


def allowed(address):
    try:
        ip = ipaddress.ip_address(address.split("%")[0])
    except ValueError:
        return False
    if ip.is_loopback:
        return True
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.version == 4 and ip in TAILNET


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if not allowed(self.client_address[0]):
            self.reply(403, "not on this Mac's network")
            return
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n).decode("utf-8"))
            provider, prompt = body.get("provider"), body.get("prompt", "")
            if provider not in PROVIDERS or not prompt.strip():
                raise ValueError("provider must be Claude or ChatGPT and prompt must not be empty")
            env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
            started = time.time()
            text = ask_claude(prompt, env) if provider == "Claude" else ask_chatgpt(prompt, env)
            sys.stderr.write("%s %s from %s answered in %.0fs\n" % (time.strftime("%H:%M:%S"), provider, self.client_address[0], time.time() - started))
            self.reply(200, text)
        except Exception as error:  # the app shows this line under Answer
            sys.stderr.write("%s failed from %s: %s\n" % (time.strftime("%H:%M:%S"), self.client_address[0], error))
            self.reply(500, str(error))

    def reply(self, status, text):
        data = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        sys.stderr.write(fmt % args + "\n")


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", 8787), Handler).serve_forever()
