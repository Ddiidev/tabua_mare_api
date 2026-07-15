#!/usr/bin/env python3
"""Wizard de reconstrução da VPS Tábua de Marés.

O modo padrão é interativo. ``--dry-run`` apenas mostra as ações e nunca abre
conexão SSH nem grava credenciais. Segredos são lidos com getpass e enviados
somente por stdin de uma sessão SSH; nunca são impressos ou persistidos.
"""
from __future__ import annotations

import argparse
import getpass
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Wizard:
    def __init__(self, args: argparse.Namespace) -> None:
        self.dry = args.dry_run
        self.host = args.host or ""
        self.user = args.user or "root"
        self.key = args.key or ""
        self.domain = args.domain or "tabuamare.api.br"
        self.image = args.image or ""
        self.coolify_backup = ""
        self.env_file = ""
        self.sqlite_a = ""
        self.sqlite_b = ""
        self.actions: list[str] = []

    def say(self, message: str) -> None:
        print(f"[recover] {message}")

    def ask(self, text: str, default: str = "") -> str:
        if default:
            value = input(f"{text} [{default}]: ").strip()
            return value or default
        return input(f"{text}: ").strip()

    def confirm(self, text: str) -> bool:
        return input(f"{text} [digite SIM]: ").strip().upper() == "SIM"

    def run(self, command: list[str], stdin: str | None = None) -> None:
        shown = " ".join(shlex.quote(x) for x in command)
        self.actions.append(shown)
        if self.dry:
            self.say(f"DRY-RUN: {shown}")
            return
        subprocess.run(command, input=stdin, text=True, check=True)

    def ssh(self, remote: str, stdin: str | None = None) -> None:
        cmd = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
        if self.key:
            cmd += ["-i", self.key]
        cmd += [f"{self.user}@{self.host}", "--", remote]
        self.run(cmd, stdin)

    def upload(self, local: Path, remote: str) -> None:
        data = local.read_text(encoding="utf-8")
        target = shlex.quote(remote)
        self.ssh(f"install -d -m 0755 /root/tabuamare-ops; cat > {target}; chmod 0755 {target}", data)

    def upload_text(self, text: str, remote: str, mode: str = "600") -> None:
        """Envia configuração por stdin, sem passar conteúdo no argv/log."""
        target = shlex.quote(remote)
        self.ssh(f"install -d -m 0700 /root/tabuamare-ops; cat > {target}; chmod {mode} {target}", text)

    def collect(self) -> None:
        if not self.host:
            self.host = self.ask("IP/hostname da nova VPS")
        if not self.key:
            self.key = self.ask("Caminho da chave SSH (vazio usa agente)")
        self.domain = self.ask("Domínio público", self.domain)
        self.image = self.ask("Imagem GHCR imutável (sha-...)", self.image)
        self.coolify_backup = self.ask("Caminho local do backup do Coolify (opcional)")
        self.env_file = self.ask("Caminho local do arquivo de ambiente A/B (opcional)")
        self.sqlite_a = self.ask("Caminho local do SQLite A (opcional)")
        self.sqlite_b = self.ask("Caminho local do SQLite B (opcional)")
        self.ask("Dados/host do PostgreSQL externo (apenas referência)")
        self.ask("Zona Cloudflare (opcional; sem automação de DNS)", self.domain)
        for label, value in (
            ("backup Coolify", self.coolify_backup),
            ("env A/B", self.env_file),
            ("SQLite A", self.sqlite_a),
            ("SQLite B", self.sqlite_b),
        ):
            if value and not Path(value).is_file():
                raise SystemExit(f"[recover] arquivo de {label} não existe: {value}")
        # Segredos são somente coletados para confirmar disponibilidade.
        if not self.dry:
            getpass.getpass("APP_KEY (não será armazenado; Enter se restaurado pelo backup): ")
            getpass.getpass("APP_PREVIOUS_KEYS (opcional): ")
            getpass.getpass("CF_DNS_API_TOKEN (Enter se já existe na VPS): ")

    def execute(self) -> None:
        self.collect()
        self.say("Ações irreversíveis exigem confirmação explícita.")
        if not self.confirm("Instalar/atualizar Ubuntu, Docker, firewall e Coolify 4.1.2 na VPS?"):
            self.say("Cancelado antes de alterar a VPS.")
            return
        if not self.dry:
            self.upload(ROOT / "ops/bootstrap_vps.sh", "/root/tabuamare-ops/bootstrap_vps.sh")
            self.upload(ROOT / "ops/cloudflare-origin-firewall.sh", "/root/tabuamare-ops/cloudflare-origin-firewall.sh")
        self.ssh("bash /root/tabuamare-ops/bootstrap_vps.sh")
        self.ssh("docker version --format '{{.Server.Version}}' && docker inspect coolify --format '{{.State.Health.Status}}'")

        dynamic = ROOT / "ops/traefik/dynamic/tabuamare.yaml"
        if dynamic.exists():
            rendered = dynamic.read_text(encoding="utf-8").replace("tabuamare.api.br", self.domain)
            self.upload_text(rendered, "/root/tabuamare-ops/tabuamare.yaml")
            self.say("Configuração Traefik renderizada e enviada para /root/tabuamare-ops/tabuamare.yaml; aplique-a no Proxy do Coolify após revisar.")

        if self.confirm("Aplicar firewall fail-closed (80/443 somente Cloudflare; portas administrativas bloqueadas)?"):
            self.ssh("/usr/local/sbin/tabuamare-cloudflare-firewall --refresh")

        self.say("A configuração do Coolify e do Traefik deve ser feita pelo painel/túnel; nenhum token é salvo pelo wizard.")
        if any((self.coolify_backup, self.env_file, self.sqlite_a, self.sqlite_b)):
            self.say("Backups/env/SQLite foram apenas validados localmente; a importação deve ser feita no Coolify/volumes após revisar o formato e o destino.")
        self.say(f"Crie/recupere tabuamare-a e tabuamare-b com a imagem {self.image or 'sha-<commit>'}, domínio {self.domain}, porta 3330 e volumes SQLite distintos.")
        self.say("Defina DNS-01 Cloudflare, Full (strict), health /health/ready e balanceamento A/B no Traefik.")
        self.say("Checklist manual: DNS A/CNAME e nameservers; callback Google OAuth; webhook e preços Stripe live; smoke HTTP; backup Coolify e rollback.")
        if self.confirm("Executar validação final (Docker, Coolify, portas e HTTPS)?"):
            self.ssh("docker ps --format '{{.Names}} {{.Status}}'; ss -ltn '( sport = :22 or sport = :80 or sport = :443 )'")
        self.say("Concluído. Segredos permanecem somente no terminal/painel; faça o cutover DNS após validar A/B.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="não conecta nem altera a VPS")
    parser.add_argument("--host", help="IP/hostname")
    parser.add_argument("--user", default="root")
    parser.add_argument("--key", help="chave SSH")
    parser.add_argument("--domain", default="tabuamare.api.br")
    parser.add_argument("--image", help="tag imutável sha-<commit>")
    args = parser.parse_args()
    try:
        Wizard(args).execute()
    except (KeyboardInterrupt, EOFError):
        print("[recover] cancelado", file=sys.stderr)
        return 130
    except subprocess.CalledProcessError as exc:
        print(f"[recover] comando falhou (código {exc.returncode}); nenhuma credencial foi exibida", file=sys.stderr)
        return exc.returncode or 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
