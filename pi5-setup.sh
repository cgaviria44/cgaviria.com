#!/usr/bin/env bash
# pi5-setup.sh — Raspberry Pi 5 + Raspberry Pi OS Lite (Debian 13 "trixie", 64-bit)
#
# Deja la Pi como nodo ligero y headless:
#   tuning   zram, journald persistente, kernel de 4K (KVM), cgroup de memoria
#   ssh      SSH solo con llave (si ya hay una en authorized_keys)
#   shell    zsh + oh-my-zsh + starship + utilidades de terminal
#   docker   Docker CE (repo oficial)
#   tailscale  Tailscale (repo oficial)
#   network  puente br0 sobre eth0 con IP fija (acceso de emergencia por cable)
#   chr      MikroTik CHR arm64 en KVM con 2 WAN: cable (ether1) y wifi/NAT (ether2)
#
# Idempotente: se puede volver a ejecutar. No instala Kali todavia.
# Uso:  ./pi5-setup.sh [--only paso,paso] [--skip paso,paso] [--list]
#       ./pi5-setup.sh                 # todo, en orden
# Debe correr como usuario normal con sudo (no como root).

set -euo pipefail
export PATH="$PATH:/usr/sbin:/sbin"

# ---------- Parametros (se pueden sobreescribir con variables de entorno) ----------
WIRED_NET="${WIRED_NET:-172.30.77}"          # /24 del puente cableado: Pi=.1, portatil=.2, CHR=.10
NAT_NET="${NAT_NET:-172.30.78}"              # /24 NAT que sale por el uplink activo (wifi): Pi=.1
CHR_NAME="${CHR_NAME:-chr}"
CHR_MGMT_IP="${CHR_MGMT_IP:-${WIRED_NET}.10}"
CHR_MEM_MB="${CHR_MEM_MB:-512}"
CHR_VCPUS="${CHR_VCPUS:-1}"
CHR_CHANNEL="${CHR_CHANNEL:-stable}"         # stable | long-term | testing
TS_HOSTNAME="${TS_HOSTNAME:-pi5}"
TS_AUTHKEY="${TS_AUTHKEY:-}"                 # opcional: auth key de Tailscale (si no, imprime un enlace)
RECREATE_CHR="${RECREATE_CHR:-0}"            # 1 = destruir y recrear la VM
FORCE_NET="${FORCE_NET:-0}"                  # 1 = permitir el paso network aunque entres por eth0
PI5_DIR=/etc/pi5                             # secretos root-only (clave de admin de CHR)
CHR_PWFILE="$PI5_DIR/chr_admin_pass"

STEPS_ALL=(base tuning ssh shell docker tailscale network chr)

# ---------- Utilidades ----------
say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32mok\033[0m  %s\n' "$*"; }
warn() { printf '    \033[33maviso\033[0m  %s\n' "$*" >&2; }
die()  { printf '\n\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
need_reboot=0

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# Escribe un archivo como root solo si cambia el contenido. Devuelve 0 si lo cambio.
put_root() { # put_root DESTINO MODO  (contenido por stdin)
  local dest="$1" mode="${2:-644}" tmp; tmp="$(mktemp)"; cat >"$tmp"
  if sudo test -f "$dest" && sudo cmp -s "$tmp" "$dest"; then rm -f "$tmp"; return 1; fi
  sudo install -D -m "$mode" "$tmp" "$dest"; rm -f "$tmp"; return 0
}

# ---------- Argumentos ----------
ONLY=""; SKIP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --skip) SKIP="$2"; shift 2 ;;
    --list) printf '%s\n' "${STEPS_ALL[@]}"; exit 0 ;;
    -h|--help) usage ;;
    *) die "argumento desconocido: $1 (usa --help)" ;;
  esac
done
want() { # want paso
  local s="$1"
  if [ -n "$ONLY" ]; then [[ ",$ONLY," == *",$s,"* ]] || return 1; fi
  [[ ",$SKIP," == *",$s,"* ]] && return 1
  return 0
}

# ---------- Comprobaciones previas ----------
preflight() {
  say "Comprobaciones previas"
  [ "$(id -u)" -ne 0 ] || die "ejecutalo como usuario normal (usa sudo por dentro), no como root"
  [ "$(uname -m)" = aarch64 ] || die "se necesita un sistema de 64 bits (aarch64); reinstala con la imagen de 64-bit"
  # shellcheck disable=SC1091
  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-}"
  case "$CODENAME" in trixie|bookworm) ok "Debian $CODENAME" ;; *) warn "Debian '$CODENAME' no probado; probado en trixie y bookworm" ;; esac
  grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null && ok "Raspberry Pi 5" || warn "no parece una Raspberry Pi 5 ($(tr -d '\0' </proc/device-tree/model 2>/dev/null))"
  sudo -n true 2>/dev/null || sudo -v || die "sudo pide contrasena y no hay terminal: ejecutalo en una sesion interactiva (ssh -t) o da sudo sin clave a tu usuario (ver README)"
  ok "usuario $USER con sudo"
}

# ---------- base ----------
step_base() {
  say "Sistema base"
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -qq full-upgrade
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl git gnupg unzip jq python3 >/dev/null
  ok "paquetes base al dia"
}

# ---------- tuning ----------
step_tuning() {
  say "Ajustes del sistema (RAM, logs, kernel)"

  # journald persistente con limite chico (sobrevive a reinicios y desgasta poco la SD/NVMe)
  put_root /etc/systemd/journald.conf.d/persistent.conf <<'EOF' && { sudo mkdir -p /var/log/journal; sudo systemctl restart systemd-journald; ok "journald persistente (50 MB)"; } || ok "journald ya configurado"
[Journal]
Storage=persistent
SystemMaxUse=50M
RuntimeMaxUse=50M
EOF

  # zram (swap comprimido en RAM). Pi OS reciente ya puede traerlo: solo se instala si falta.
  if sudo swapon --show=NAME --noheadings | grep -q zram; then
    ok "zram ya activo"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq zram-tools >/dev/null
    printf 'ALGO=zstd\nPERCENT=50\nPRIORITY=100\n' | sudo tee /etc/default/zramswap >/dev/null
    sudo systemctl enable zramswap >/dev/null 2>&1
    sudo systemctl restart zramswap
    ok "zram activado (50% de la RAM, zstd)"
  fi
  sudo systemctl disable --now dphys-swapfile >/dev/null 2>&1 || true   # no hacer swap en la SD
  put_root /etc/sysctl.d/99-zram.conf <<'EOF' && sudo sysctl --system >/dev/null || true
vm.swappiness=100
vm.page-cluster=0
EOF

  # Kernel de 4K: el de 16K (por defecto en Pi 5) da problemas con KVM/UEFI de algunos invitados
  local cfg=/boot/firmware/config.txt cmd=/boot/firmware/cmdline.txt
  if [ -f /boot/firmware/kernel8.img ]; then
    if ! grep -q '^kernel=kernel8.img' "$cfg"; then
      sudo cp -n "$cfg" "$cfg.pre-pi5"
      printf '\n[all]\nkernel=kernel8.img\n' | sudo tee -a "$cfg" >/dev/null
      need_reboot=1; ok "kernel de 4K activado en config.txt (respaldo: config.txt.pre-pi5)"
    else ok "kernel de 4K ya configurado"; fi
  else
    warn "no existe /boot/firmware/kernel8.img; no cambio el kernel"
  fi

  # cgroup de memoria: sin esto Docker ignora --memory
  if ! grep -q 'cgroup_memory=1' "$cmd"; then
    sudo cp -n "$cmd" "$cmd.pre-pi5"
    sudo sed -i '1s/$/ cgroup_enable=memory cgroup_memory=1/' "$cmd"
    need_reboot=1; ok "cgroup de memoria activado en cmdline.txt (respaldo: cmdline.txt.pre-pi5)"
  else ok "cgroup de memoria ya configurado"; fi
  [ "$(wc -l <"$cmd")" -le 1 ] || die "cmdline.txt debe ser UNA sola linea; restaura $cmd.pre-pi5"
}

# ---------- ssh ----------
step_ssh() {
  say "SSH solo con llave"
  if [ -s "$HOME/.ssh/authorized_keys" ]; then
    put_root /etc/ssh/sshd_config.d/00-keys-only.conf <<'EOF' && { sudo sshd -t && sudo systemctl reload ssh; ok "login por contrasena desactivado"; } || ok "ya estaba configurado"
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  else
    warn "no hay llaves en ~/.ssh/authorized_keys: NO desactivo la contrasena (te dejaria fuera)"
    warn "pon tu llave publica con Raspberry Pi Imager o 'ssh-copy-id' y vuelve a ejecutar: $0 --only ssh"
  fi
}

# ---------- shell ----------
step_shell() {
  say "Terminal: zsh + oh-my-zsh + starship"
  local p
  for p in zsh git curl fzf bat ripgrep fd-find eza tmux btop; do
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$p" >/dev/null 2>&1 || warn "no pude instalar $p (sigo)"
  done

  [ -d "$HOME/.oh-my-zsh" ] || git clone -q --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  ok "oh-my-zsh"

  # starship: binario oficial arm64 con verificacion de hash
  if ! [ -x "$HOME/.local/bin/starship" ]; then
    local t base=https://github.com/starship/starship/releases/latest/download f=starship-aarch64-unknown-linux-musl.tar.gz
    t="$(mktemp -d)"
    curl -fsSL "$base/$f" -o "$t/$f"
    curl -fsSL "$base/$f.sha256" -o "$t/$f.sha256"
    ( cd "$t" && echo "$(cut -d' ' -f1 "$f.sha256")  $f" | sha256sum -c - >/dev/null ) || die "el hash de starship no coincide"
    mkdir -p "$HOME/.local/bin"; tar xzf "$t/$f" -C "$HOME/.local/bin" starship; rm -rf "$t"
  fi
  ok "starship $("$HOME/.local/bin/starship" --version | head -1)"

  # .zshrc (se respalda el original una sola vez)
  local rc="$HOME/.zshrc" new; new="$(mktemp)"
  cat >"$new" <<'EOF'
# pi5-setup managed — se regenera con ./pi5-setup.sh --only shell (tu original: ~/.zshrc.pre-pi5)
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
# autosuggestions/highlighting desactivados: en algunas terminales por SSH el redibujado sale roto
plugins=(git z history)
source $ZSH/oh-my-zsh.sh

export PATH="$HOME/.local/bin:$PATH"
export HISTSIZE=10000 SAVEHIST=10000
setopt HIST_IGNORE_DUPS SHARE_HISTORY

# nombres de Debian para estas utilidades
command -v batcat  >/dev/null && alias bat=batcat
command -v fdfind  >/dev/null && alias fd=fdfind
command -v eza     >/dev/null && alias ll='eza -lah --git' && alias lt='eza --tree --level=2'
command -v fzf     >/dev/null && source <(fzf --zsh 2>/dev/null)

# apaga el modo raton de la terminal antes de cada prompt (evita 64;46;15M... al hacer scroll
# cuando un programa muere sin restaurarlo, p. ej. una sesion SSH cortada dentro de un TUI)
autoload -Uz add-zsh-hook
_reset_mouse() { printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l' }
add-zsh-hook precmd _reset_mouse

eval "$(starship init zsh)"
EOF
  if ! cmp -s "$new" "$rc"; then
    [ -f "$rc" ] && ! grep -q 'pi5-setup managed' "$rc" && cp -n "$rc" "$rc.pre-pi5"
    install -m 644 "$new" "$rc"
  fi
  rm -f "$new"

  mkdir -p "$HOME/.config"
  cat >"$HOME/.config/starship.toml" <<'EOF'
add_newline = true
command_timeout = 500

format = """$username$directory$hostname$git_branch$git_status$python$docker_context$cmd_duration
$jobs$status$character"""

[character]
success_symbol = "[❯ ](bold green)"
error_symbol = "[❯ ](bold red)"

[directory]
truncation_length = 2
truncate_to_repo = false

[username]
show_always = true
format = "[$user]($style) "
style_user = "bold yellow"

[hostname]
ssh_only = false
format = "en [$hostname]($style) "
style = "bold green"

[git_branch]
symbol = " "
format = "en [$symbol$branch]($style) "

[git_status]
format = "([$all_status$ahead_behind]($style) )"

[cmd_duration]
min_time = 2000
format = "tomó [$duration]($style) "

[status]
disabled = false
format = "[$status]($style) "

[jobs]
format = "[$symbol$number]($style) "

[python]
format = "[$symbol$version]($style) "

[docker_context]
format = "[$symbol$context]($style) "
EOF
  sudo chsh -s "$(command -v zsh)" "$USER"
  ok "zsh como shell de login (los iconos necesitan una Nerd Font en tu terminal cliente)"
}

# ---------- docker ----------
step_docker() {
  say "Docker CE"
  # shellcheck disable=SC1091
  . /etc/os-release; local cn="$VERSION_CODENAME"
  if ! have docker; then
    curl -fsI "https://download.docker.com/linux/debian/dists/$cn/Release" >/dev/null || die "Docker no publica repo para '$cn'"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $cn stable" |
      sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  fi
  # logs acotados para no llenar la SD
  [ -f /etc/docker/daemon.json ] || {
    echo '{"log-driver":"local","log-opts":{"max-size":"10m","max-file":"3"}}' | sudo install -D -m 644 /dev/stdin /etc/docker/daemon.json
    sudo systemctl restart docker
  }
  sudo systemctl enable --now docker >/dev/null 2>&1
  sudo usermod -aG docker "$USER"
  sudo docker run --rm hello-world >/dev/null 2>&1 && ok "Docker $(sudo docker version --format '{{.Server.Version}}') funcionando" || warn "hello-world fallo"
  warn "para usar docker sin sudo, cierra y abre la sesion SSH (grupo docker)"
}

# ---------- tailscale ----------
step_tailscale() {
  say "Tailscale"
  # shellcheck disable=SC1091
  . /etc/os-release; local cn="$VERSION_CODENAME"
  if ! have tailscale; then
    curl -fsI "https://pkgs.tailscale.com/stable/debian/$cn.noarmor.gpg" >/dev/null || die "Tailscale no publica repo para '$cn'"
    sudo curl -fsSL "https://pkgs.tailscale.com/stable/debian/$cn.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    sudo curl -fsSL "https://pkgs.tailscale.com/stable/debian/$cn.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale >/dev/null
  fi
  sudo systemctl enable --now tailscaled >/dev/null 2>&1
  if sudo tailscale status >/dev/null 2>&1; then
    ok "ya conectado a la tailnet: $(tailscale ip -4 2>/dev/null | head -1)"
  else
    say "Autoriza este dispositivo abriendo el enlace que aparece abajo (espero hasta 10 min)"
    sudo tailscale up --hostname="$TS_HOSTNAME" --timeout=10m ${TS_AUTHKEY:+--auth-key="$TS_AUTHKEY"} || warn "no se completo el login; repite: sudo tailscale up --hostname=$TS_HOSTNAME"
  fi
}

# ---------- network ----------
step_network() {
  say "Puente br0 con IP fija sobre eth0 (acceso de emergencia por cable)"
  have nmcli && systemctl is-active --quiet NetworkManager || die "se necesita NetworkManager activo (viene con Raspberry Pi OS)"
  ip link show eth0 >/dev/null 2>&1 || die "no existe eth0"

  # Salvaguarda: meter eth0 en un puente sin DHCP te deja sin SSH si entras por el cable
  local via=""
  [ -n "${SSH_CONNECTION:-}" ] && via="$(ip -o route get "${SSH_CONNECTION%% *}" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)"
  [ -n "$via" ] || via="$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)"
  if [ "$via" = eth0 ] && [ "$FORCE_NET" != 1 ]; then
    die "estas conectado por eth0: este paso te cortaria la sesion. Conectate por wifi (o consola) o usa FORCE_NET=1"
  fi

  if nmcli -t -f NAME con show | grep -qx br0; then
    ok "br0 ya existe ($(nmcli -g ipv4.addresses con show br0))"
  else
    sudo nmcli con add type bridge ifname br0 con-name br0 \
      ipv4.method manual ipv4.addresses "${WIRED_NET}.1/24" ipv4.never-default yes \
      ipv6.method disabled bridge.stp no connection.autoconnect yes >/dev/null
    sudo nmcli con add type ethernet ifname eth0 con-name br0-eth0 slave-type bridge master br0 >/dev/null
    # perfiles cableados antiguos (DHCP) no deben competir por eth0
    nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /ethernet/ && $1 != "br0-eth0" {print $1}' | while read -r n; do
      sudo nmcli con mod "$n" connection.autoconnect no
    done
    sudo nmcli con up br0 >/dev/null 2>&1 || true   # queda "waiting for slaves" hasta que haya cable: es normal
    ok "br0 creado: ${WIRED_NET}.1/24 (sin gateway, sin DHCP server a proposito)"
  fi
}

# ---------- chr ----------
virsh_() { sudo virsh -c qemu:///system "$@"; }

install_chr_console() {
  # Ayudante para manejar la consola serie de RouterOS (sin red): lo usan el aprovisionamiento y el apagado limpio
  sudo install -D -m 755 /dev/stdin /usr/local/bin/chr-console <<'PYEOF'
#!/usr/bin/env python3
"""chr-console — maneja la consola serie de la VM CHR (RouterOS) via virsh.

  chr-console [--vm NOMBRE] [--init] [--shutdown] ['/comando' ...]

  --init      primer arranque: fija la clave de admin (la guarda /etc/pi5/chr_admin_pass) y verifica
  --shutdown  apagado limpio con /system shutdown (CHR arm64 NO responde al apagado ACPI)
Sin opciones ejecuta los comandos RouterOS dados. Debe correr como root (sudo)."""
import os, pty, re, select, subprocess, sys, time

PROMPT = "[admin@"
args = sys.argv[1:]
vm = os.environ.get("CHR_NAME", "chr")
init = shutdown = False
cmds = []
while args:
    a = args.pop(0)
    if a == "--vm": vm = args.pop(0)
    elif a == "--init": init = True
    elif a == "--shutdown": shutdown = True
    else: cmds.append(a)
pwfile = os.environ.get("CHR_PWFILE", "/etc/pi5/chr_admin_pass")
pw = open(pwfile).read().strip()

def open_console():
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("virsh", ["virsh", "-c", "qemu:///system", "console", vm])
    return pid, fd

def clean(b):
    t = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", b.decode(errors="replace")).replace("\r", "")
    return t.replace(pw, "<PW>")

class Con:
    def __init__(self):
        self.pid, self.fd = open_console()
    def rd(self, t):
        end, out = time.time() + t, b""
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.3)
            if r:
                try: d = os.read(self.fd, 4096)
                except OSError: break
                if not d: break
                out += d
        return clean(out)
    def send(self, s, t=2):
        try: os.write(self.fd, s.encode())
        except OSError: return ""
        return self.rd(t)
    def expect(self, pats, timeout, send=None):
        """Espera hasta ver alguno de los textos (o agotar el tiempo). Devuelve (texto_visto|None, salida)."""
        if send is not None:
            try: os.write(self.fd, send.encode())
            except OSError: return None, ""
        end, buf = time.time() + timeout, ""
        while time.time() < end:
            buf += self.rd(0.5)
            for p in pats:
                if p in buf: return p, buf
        return None, buf
    def close(self):
        try: os.write(self.fd, b"\x1d")
        except OSError: pass
        try: os.close(self.fd)
        except OSError: pass
        try: os.waitpid(self.pid, 0)
        except OSError: pass

def login(c, allow_blank):
    """Llega a un prompt de RouterOS. Devuelve 'pw' o 'blank' segun la clave que funciono."""
    for _ in range(3): c.send("\x03", 1)
    deadline = time.time() + 240               # el arranque puede tardar
    while True:
        p, _ = c.expect(["Login:", PROMPT, "new password>", "Password:"], 3, send="\r")
        if p: break
        if time.time() > deadline: raise SystemExit("la consola no responde")
    if p == PROMPT: return "pw"
    if p in ("new password>", "Password:"):    # dialogo o clave colgados de un intento anterior
        for _ in range(3): c.send("\x03", 1)
        p, _ = c.expect(["Login:", PROMPT], 10, send="\r")
        if p == PROMPT: return "pw"
    if p != "Login:": raise SystemExit("no llego al prompt de Login")
    c.expect(["Password:"], 5, send="admin\r")
    p, _ = c.expect([PROMPT, "Login:", "new password>"], 15, send=pw + "\r")
    if p == PROMPT: return "pw"
    if not allow_blank: raise SystemExit("login rechazado con la clave guardada")
    if p == "Login:": c.expect(["Password:"], 5, send="admin\r")
    # clave vacia: el PRIMER login de una imagen nueva tarda (>6 s) en mostrar el dialogo
    p, _ = c.expect(["new password>", PROMPT], 60, send="\r")
    if p == "new password>":
        c.expect(["repeat new password>"], 10, send=pw + "\r")
        p, _ = c.expect([PROMPT, "do not match", "same as old"], 15, send=pw + "\r")
        if p == PROMPT: return "blank"
        p, _ = c.expect([PROMPT], 10, send="\x03")     # cancelar el dialogo
    if p != PROMPT: raise SystemExit("no pude entrar con clave vacia")
    # entro saltando el dialogo: /password (no /user set) es lo que quita la marca EXPIRED
    c.send('/password old-password="" new-password="%s" confirm-new-password="%s"\r' % (pw, pw), 4)
    return "blank"

def run(c, cs):
    out = ""
    for x in cs: out += c.send(x + "\r", 3)
    return out

if shutdown:                                  # si la VM no esta corriendo no hay nada que apagar
    st = subprocess.run(["virsh", "-c", "qemu:///system", "domstate", vm], capture_output=True, text=True).stdout
    if "running" not in st:
        print("la VM no esta corriendo; nada que apagar", file=sys.stderr)
        sys.exit(0)

c = Con()
try:
    how = login(c, allow_blank=init)
    if init:
        c.close(); time.sleep(1); c = Con()
        if login(c, allow_blank=False) != "pw": raise SystemExit("verificacion: login con clave fallo")
        users = run(c, ["/user print"])
        if re.search(r"^\s*\d+\s+E\s+admin", users, re.M): raise SystemExit("verificacion: admin sigue EXPIRED")
        print("clave de admin fijada y verificada (", how, ")", file=sys.stderr)
    if cmds: print(run(c, cmds))
    if shutdown:
        c.send("/system shutdown\r", 2); c.send("y\r", 2)
        for _ in range(30):
            st = subprocess.run(["virsh", "-c", "qemu:///system", "domstate", vm], capture_output=True, text=True).stdout
            if "shut off" in st: break
            time.sleep(2)
        else: raise SystemExit("la VM no se apago en 60 s")
        print("CHR apagado limpio", file=sys.stderr)
finally:
    c.close()
PYEOF
}

step_chr() {
  say "MikroTik CHR arm64 en KVM (2 WAN: cable + wifi/NAT)"
  if [ "$(getconf PAGESIZE)" != 4096 ]; then
    # el kernel de 4K solo se estrena tras reiniciar: si ya esta configurado, se salta este paso sin error
    if grep -q '^kernel=kernel8.img' /boot/firmware/config.txt; then
      need_reboot=1; warn "el kernel de 4K aun no esta activo: salto el paso chr; reinicia (sudo reboot) y vuelve a ejecutar $0"; return 0
    fi
    die "el kernel usa paginas de 16K y no hay kernel8.img configurado: ejecuta antes el paso tuning"
  fi
  [ -e /dev/kvm ] || die "no existe /dev/kvm"
  ip link show br0 >/dev/null 2>&1 || die "falta br0: ejecuta primero el paso network"

  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-system-arm qemu-utils qemu-efi-aarch64 \
    libvirt-daemon-system libvirt-clients virtinst unzip curl python3 >/dev/null
  sudo systemctl enable --now libvirtd >/dev/null 2>&1
  sudo usermod -aG libvirt,kvm "$USER"

  # redes libvirt: 'wired' (puente a br0) y 'wifi-nat' (NAT por el uplink que haya, normalmente wlan0)
  local n xml
  for n in wired wifi-nat; do
    if ! virsh_ net-info "$n" >/dev/null 2>&1; then
      if [ "$n" = wired ]; then xml="<network><name>wired</name><forward mode='bridge'/><bridge name='br0'/></network>"
      else xml="<network><name>wifi-nat</name><forward mode='nat'/><bridge name='virbr-nat' stp='off' delay='0'/><ip address='${NAT_NET}.1' netmask='255.255.255.0'><dhcp><range start='${NAT_NET}.10' end='${NAT_NET}.50'/></dhcp></ip></network>"; fi
      f="$(mktemp)"; echo "$xml" >"$f"        # archivo del usuario: un 'sudo tee' en /tmp (sticky) no se podria borrar luego
      virsh_ net-define "$f" >/dev/null; rm -f "$f"
    fi
    virsh_ net-start "$n" >/dev/null 2>&1 || true
    virsh_ net-autostart "$n" >/dev/null
  done
  ok "redes libvirt wired y wifi-nat"

  install_chr_console
  sudo install -d -m 700 "$PI5_DIR"
  if ! sudo test -s "$CHR_PWFILE"; then
    local pw; pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"   # '|| true': tr muere por SIGPIPE y pipefail abortaria
    [ "${#pw}" -eq 20 ] || die "no pude generar la clave de admin"
    printf '%s\n' "$pw" | sudo install -m 600 /dev/stdin "$CHR_PWFILE"
    ok "clave de admin de CHR generada en $CHR_PWFILE (solo root)"
  fi

  if virsh_ dominfo "$CHR_NAME" >/dev/null 2>&1; then
    if [ "$RECREATE_CHR" = 1 ]; then
      virsh_ destroy "$CHR_NAME" >/dev/null 2>&1 || true
      virsh_ undefine "$CHR_NAME" --nvram >/dev/null
      sudo rm -f "/var/lib/libvirt/images/$CHR_NAME.qcow2"
    else
      ok "la VM '$CHR_NAME' ya existe (RECREATE_CHR=1 para recrearla); no la toco"
      virsh_ autostart "$CHR_NAME" >/dev/null
      return 0
    fi
  fi

  # descarga oficial (solo download.mikrotik.com)
  local ver t; ver="$(curl -fsS "https://upgrade.mikrotik.com/routeros/NEWESTa7.$CHR_CHANNEL" | cut -d' ' -f1)"
  [ -n "$ver" ] || die "no pude averiguar la version de RouterOS ($CHR_CHANNEL)"
  t="$(mktemp -d)"
  curl -fsSL "https://download.mikrotik.com/routeros/$ver/chr-$ver-arm64.img.zip" -o "$t/chr.zip"
  ok "CHR $ver ($CHR_CHANNEL) descargado; sha256: $(sha256sum "$t/chr.zip" | cut -d' ' -f1)"
  unzip -q "$t/chr.zip" -d "$t"
  sudo qemu-img convert -f raw -O qcow2 "$t/chr-$ver-arm64.img" "/var/lib/libvirt/images/$CHR_NAME.qcow2"
  rm -rf "$t"

  # IMPORTANTE: firmware SIN Secure Boot (AAVMF_CODE.fd). El .ms.fd que libvirt elige solo rechaza el cargador de MikroTik.
  sudo virt-install --connect qemu:///system --name "$CHR_NAME" --memory "$CHR_MEM_MB" --vcpus "$CHR_VCPUS" \
    --cpu host-passthrough --machine virt \
    --boot "loader=/usr/share/AAVMF/AAVMF_CODE.fd,loader.readonly=yes,loader.type=pflash,nvram.template=/usr/share/AAVMF/AAVMF_VARS.fd,nvram=/var/lib/libvirt/qemu/nvram/${CHR_NAME}_VARS.fd" \
    --import --disk "path=/var/lib/libvirt/images/$CHR_NAME.qcow2,bus=virtio" \
    --network network=wired,model=virtio --network network=wifi-nat,model=virtio \
    --graphics none --osinfo detect=on,require=off --noautoconsole >/dev/null
  virsh_ autostart "$CHR_NAME" >/dev/null
  ok "VM '$CHR_NAME' creada: ether1 = cable (br0), ether2 = wifi/NAT"

  say "Aprovisionando RouterOS por la consola serie (puede tardar ~1-2 min)"
  CHR_NAME="$CHR_NAME" sudo -E chr-console --vm "$CHR_NAME" --init \
    '/interface ethernet set ether1 comment="WAN cable (br0)"' \
    '/interface ethernet set ether2 comment="WAN wifi (NAT)"' \
    '/ip dhcp-client remove [find]' \
    '/ip dhcp-client add interface=ether1 add-default-route=yes default-route-distance=1 use-peer-dns=yes comment="WAN cable"' \
    '/ip dhcp-client add interface=ether2 add-default-route=yes default-route-distance=2 use-peer-dns=yes comment="WAN wifi"' \
    "/ip address add address=${CHR_MGMT_IP}/24 interface=ether1 comment=\"gestion por cable\"" \
    '/ip service disable telnet,ftp,www,api,api-ssl' \
    '/ip firewall filter add chain=input connection-state=established,related action=accept comment="est/rel"' \
    '/ip firewall filter add chain=input protocol=icmp action=accept comment="icmp"' \
    "/ip firewall filter add chain=input src-address=${WIRED_NET}.0/24 action=accept comment=\"gestion por cable\"" \
    "/ip firewall filter add chain=input src-address=${NAT_NET}.1 action=accept comment=\"gestion desde la Pi\"" \
    '/ip firewall filter add chain=input action=drop comment="drop resto de input (WAN)"' >/dev/null
  ok "RouterOS configurado: gestion en ${CHR_MGMT_IP} (ssh/winbox solo desde ${WIRED_NET}.0/24 y la Pi)"

  # Apagado limpio de CHR al apagar/reiniciar la Pi (ACPI no funciona con CHR arm64)
  put_root /etc/systemd/system/chr-graceful.service <<EOF || true
[Unit]
Description=Apagado ordenado de la VM MikroTik CHR
After=libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=CHR_NAME=$CHR_NAME
ExecStart=/bin/true
ExecStop=/usr/local/bin/chr-console --vm $CHR_NAME --shutdown
TimeoutStopSec=70

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload; sudo systemctl enable --now chr-graceful.service >/dev/null 2>&1
  ok "servicio chr-graceful (apaga CHR con /system shutdown antes de apagar la Pi)"
}

# ---------- resumen ----------
summary() {
  say "Listo"
  [ "$need_reboot" = 1 ] && warn "se cambio el arranque (kernel/cgroup): reinicia con 'sudo reboot' y vuelve a ejecutar '$0' para completar el paso chr"
  want network && echo "  Acceso de emergencia por cable : ssh $USER@${WIRED_NET}.1   (tu portatil: ${WIRED_NET}.2/24, sin gateway)"
  if want chr && [ "$need_reboot" != 1 ]; then
    echo "  CHR (gestion)                 : ${CHR_MGMT_IP}  usuario admin   (Winbox: Connect To ${CHR_MGMT_IP})"
    echo "  Clave de admin de CHR          : sudo cat $CHR_PWFILE"
    echo "  Consola de CHR sin red         : sudo chr-console '/ip address print'"
    echo "  Apagado limpio                 : sudo systemctl poweroff   (chr-graceful apaga CHR antes)"
  fi
  want docker && echo "  Docker sin sudo                : cierra y abre la sesion SSH"
  return 0
}

# ---------- ejecucion ----------
preflight
CODENAME="${CODENAME:-}"
for s in "${STEPS_ALL[@]}"; do
  want "$s" || continue
  "step_$s"
done
summary
