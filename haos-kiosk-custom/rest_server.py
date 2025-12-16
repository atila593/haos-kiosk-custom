import os
import asyncio
from aiohttp import web
import re
import logging
import sys
import json
import contextlib

# Configuration des logs
logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s: [%(filename)s] %(message)s",
    datefmt="%H:%M:%S"
)

# Variables d'environnement
ALLOW_USER_COMMANDS = os.getenv("ALLOW_USER_COMMANDS", "false").lower() == "true"
REST_PORT = int(os.getenv("REST_PORT", 8080))
REST_BEARER_TOKEN = os.getenv("REST_BEARER_TOKEN")
# CORRECTION : Doit être 0.0.0.0 pour être accessible depuis l'extérieur
REST_IP = "0.0.0.0" 

MAX_PROCS = 5
_SUBPROC_SEM = asyncio.Semaphore(MAX_PROCS)
_current_procs = set()

def is_valid_url(url):
    regex = re.compile(r'^(https?://)?(?:localhost|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|[a-z0-9.-]+)(?::\d+)?(?:/.*)?$', re.IGNORECASE)
    return re.match(regex, url) is not None

def sanitize_command(cmd):
    if re.search(r'[&|<>]', cmd):
        raise ValueError("Command contains invalid characters")
    return cmd

# CORRECTION : Commande pour Matchbox-keyboard au lieu de Onboard
async def toggle_matchbox_keyboard(log_prefix: str = "toggle_keyboard"):
    """Bascule la visibilité du clavier via xdotool."""
    # On simule la combinaison de touches configurée dans ton gestionnaire de fenêtres
    command = "export DISPLAY=:0 && xdotool key ctrl+alt+k"
    result = await run_command(command, log_prefix)
    return result

async def run_command(command: str, log_prefix: str, cmd_timeout: int = None):
    async with _SUBPROC_SEM:
        # On s'assure que DISPLAY est toujours défini pour les outils X11
        full_command = f"export DISPLAY=:0 && {command}"
        proc = await asyncio.create_subprocess_shell(
            full_command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        _current_procs.add(proc)
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=cmd_timeout) if cmd_timeout else await proc.communicate()
            return {"success": proc.returncode == 0, "stdout": stdout.decode().strip(), "stderr": stderr.decode().strip()}
        except Exception as e:
            with contextlib.suppress(ProcessLookupError): proc.kill()
            return {"success": False, "error": str(e)}
        finally:
            _current_procs.discard(proc)

# Gestionnaires de requêtes
async def handle_toggle_keyboard(request):
    logging.info("[toggle_keyboard] Basculement du clavier Matchbox")
    result = await toggle_matchbox_keyboard()
    return web.json_response(result)

async def handle_display_on(request):
    return web.json_response(await run_command("xset dpms force on", "display_on"))

async def handle_display_off(request):
    return web.json_response(await run_command("xset dpms force off", "display_off"))

# ... (garde tes autres fonctions handle_launch_url, etc. ici) ...

async def main():
    app = web.Application() # Ajoute tes middlewares ici si besoin
    app.router.add_post("/keyboard/toggle", handle_toggle_keyboard)
    app.router.add_post("/display_on", handle_display_on)
    app.router.add_post("/display_off", handle_display_off)
    
    logging.info(f"[main] Serveur REST prêt sur http://{REST_IP}:{REST_PORT}")
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, REST_IP, REST_PORT)
    await site.start()
    await asyncio.Event().wait()

if __name__ == "__main__":
    asyncio.run(main())
