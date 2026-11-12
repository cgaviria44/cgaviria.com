# pi5 — Raspberry Pi 5 como nodo ligero

Script para dejar una **Raspberry Pi 5** lista a partir de una instalación limpia de
**Raspberry Pi OS Lite (64-bit, Debian 13 «trixie»)**: headless, con Docker, Tailscale, una terminal
cómoda y un **MikroTik CHR arm64** corriendo en KVM con dos WAN.

> Esta rama (`pi5`) es **huérfana**: no comparte historial ni archivos con el sitio del CV de `main`.
> Solo contiene este README y `pi5-setup.sh`.

## Qué instala y configura

| Paso | Qué hace |
|---|---|
| `base` | `apt full-upgrade` y paquetes base (`curl`, `git`, `jq`, `python3`, …) |
| `tuning` | journald persistente (50 MB), zram si no existe, kernel de **4K** (`kernel=kernel8.img`) y cgroup de memoria |
| `ssh` | SSH **solo con llave** (solo si ya hay una en `authorized_keys`, para no dejarte fuera) |
| `shell` | `zsh` + oh-my-zsh + [starship](https://starship.rs) + `fzf`, `bat`, `ripgrep`, `fd`, `eza`, `tmux`, `btop` |
| `docker` | Docker CE desde el repo oficial, con logs acotados |
| `tailscale` | Tailscale desde el repo oficial; imprime el enlace para autorizar el equipo |
| `network` | Puente `br0` sobre `eth0` con **IP fija** (acceso de emergencia por cable, sin DHCP server) |
| `chr` | libvirt/QEMU, redes `wired` y `wifi-nat`, VM **MikroTik CHR** y su aprovisionamiento por consola serie |

**No** instala Kali (queda para después), ni configura adaptadores USB wifi.

## Diseño de red

```
 Portátil ──cable──[eth0]──┐
                           br0  172.30.77.1/24  (IP fija de la Pi, sin gateway)
                            │
                            └── CHR ether1  172.30.77.10/24 + DHCP-client  (WAN por cable)

 Internet ◄── wlan0 ◄── NAT libvirt 172.30.78.0/24 ◄── CHR ether2  DHCP-client (WAN por wifi)
```

- **Acceso de emergencia:** `br0` tiene IP fija, así que desde un portátil por cable (`172.30.77.2/24`,
  sin gateway) entras a `172.30.77.1` sin depender de ninguna red Wi-Fi, pantalla ni teclado.
- **CHR tiene exactamente 2 interfaces:** `ether1` (cable, puenteada a `br0`) y `ether2` (wifi, por NAT).
  Una interfaz Wi-Fi cliente no se puede puentear con una VM, por eso la segunda sale por NAT a través
  de `wlan0`.
- **Rutas por defecto:** `ether1` con distancia 1 (si conectas el cable a un router con DHCP, es la preferida)
  y `ether2` con distancia 2 (respaldo por wifi).
- **Subredes** `172.30.77.0/24` y `172.30.78.0/24`: elegidas raras a propósito para no chocar con redes de casa
  u oficina (`192.168.x`, `10.x`) ni con el `172.31.0.0/16` típico de las VPC de AWS. Se pueden cambiar con
  `WIRED_NET` y `NAT_NET`.
- **Sin servidor DHCP en el cable**, a propósito: así, si conectas la Pi a una red ajena, no reparte IPs.

## Uso

### 1. Flashear
Con [Raspberry Pi Imager](https://www.raspberrypi.com/software/): **Raspberry Pi OS Lite (64-bit)**. En
*Personalizar*: nombre de equipo, tu usuario, **tu llave pública SSH**, y la **Wi-Fi** con el país correcto.
Recomendado: un **NVMe** (HAT M.2) en lugar de la SD si vas a usar Docker y VMs.

### 2. Descargar y leer el script
Entra por SSH (por Wi-Fi) y descarga el script. **Léelo antes de ejecutarlo**; hace cambios de sistema con `sudo`.

```bash
curl -fsSLO https://raw.githubusercontent.com/cgaviria44/cgaviria.com/pi5/pi5-setup.sh
less pi5-setup.sh
chmod +x pi5-setup.sh
```

### 3. Ejecutar (dos pasadas)
```bash
./pi5-setup.sh          # 1.ª pasada: todo menos chr; termina pidiendo reinicio
sudo reboot
./pi5-setup.sh          # 2.ª pasada: ya con el kernel de 4K, crea y configura CHR
```
Es **idempotente**: puedes repetirlo; lo que ya está hecho se salta. También:

```bash
./pi5-setup.sh --list                 # pasos disponibles
./pi5-setup.sh --only shell,docker    # solo esos pasos
./pi5-setup.sh --skip chr             # todo menos chr
```

> **Ejecútalo conectado por Wi-Fi o por consola, no por `eth0`.** El paso `network` mete `eth0` en un puente
> sin DHCP y cortaría tu sesión. El script lo detecta y se niega (`FORCE_NET=1` para forzarlo).

### 4. Tailscale
El paso `tailscale` imprime un enlace; ábrelo y aprueba el dispositivo (o pasa `TS_AUTHKEY=…` si usas una auth key).

### 5. Portátil por cable
Pon el Ethernet del portátil en **IP manual `172.30.77.2`, máscara `255.255.255.0`, sin router**, y entra con
`ssh usuario@172.30.77.1`. CHR queda en `172.30.77.10`: en Winbox usa *Connect To* `172.30.77.10`.

## Variables de entorno

| Variable | Por defecto | Para qué |
|---|---|---|
| `WIRED_NET` | `172.30.77` | /24 del puente cableado (Pi `.1`, portátil `.2`, CHR `.10`) |
| `NAT_NET` | `172.30.78` | /24 del NAT hacia el uplink (Pi `.1`) |
| `CHR_NAME` | `chr` | nombre de la VM |
| `CHR_MGMT_IP` | `${WIRED_NET}.10` | IP de gestión de CHR en `ether1` |
| `CHR_MEM_MB` / `CHR_VCPUS` | `512` / `1` | recursos de la VM |
| `CHR_CHANNEL` | `stable` | `stable`, `long-term` o `testing` |
| `RECREATE_CHR` | `0` | `1` destruye y recrea la VM |
| `TS_HOSTNAME` / `TS_AUTHKEY` | `pi5` / vacío | nombre en la tailnet y auth key opcional |
| `FORCE_NET` | `0` | permite el paso `network` aunque entres por `eth0` |

## MikroTik CHR

- **Descarga oficial** desde `download.mikrotik.com`; el script imprime el SHA-256 del `.zip`.
- **Clave de `admin`:** generada aleatoriamente y guardada en `/etc/pi5/chr_admin_pass` (solo root):
  `sudo cat /etc/pi5/chr_admin_pass`. Cámbiala por la tuya y guárdala en un gestor de contraseñas.
- **Endurecido por defecto** (la WAN puede estar en una red ajena): se deshabilitan `telnet`, `ftp`, `www`,
  `api` y `api-ssl`; el cortafuegos de entrada solo permite *established/related*, ICMP y gestión desde
  `172.30.77.0/24` y la propia Pi. El cliente DHCP sigue funcionando.
- **Consola sin red:** `sudo chr-console '/ip address print'` (usa la consola serie de la VM).
- **Licencia:** la instancia arm64 tiene un `system-id` nuevo; asocia tu licencia desde tu cuenta de MikroTik.
  Sin licencia corre en modo `free` (límite de 1 Mbps por interfaz).

### Trampas conocidas (resueltas por el script)
- **Firmware UEFI sin Secure Boot.** libvirt elige por defecto `AAVMF_CODE.ms.fd` (Secure Boot con claves de
  Microsoft) y rechaza el cargador de MikroTik: la VM se queda en el menú de UEFI. Se usa `AAVMF_CODE.fd`.
- **CHR arm64 no responde al apagado ACPI** (`virsh shutdown` no hace nada). El script instala el servicio
  `chr-graceful`, que ejecuta `/system shutdown` por la consola antes de apagar o reiniciar la Pi.
- **Clave de `admin` y marca `EXPIRED`.** Cancelar el diálogo de «new password» deja `admin` con la clave
  **vacía** y marcado `E - EXPIRED`; `/user set admin password=` **no** quita la marca (Winbox dice
  «wrong password»). Lo correcto es `/password old-password="" new-password=… confirm-new-password=…`, que es
  lo que hace el script, y verifica que una clave falsa se rechace.
- **Kernel de 16K de la Pi 5.** Para KVM con UEFI se usa el kernel de 4K (`kernel=kernel8.img`); requiere
  reiniciar, de ahí las dos pasadas.

## Terminal

- **Fuente:** el prompt usa iconos; instala una *Nerd Font* (p. ej. `MesloLGS NF`) en la terminal del cliente.
- **Terminfo de Ghostty** (si usas [Ghostty](https://ghostty.org) en el cliente), una vez, desde tu equipo:
  ```bash
  infocmp -x xterm-ghostty | ssh usuario@IP 'tic -x -'
  ```
- Se dejan **desactivados** `zsh-autosuggestions` y `zsh-syntax-highlighting`: por SSH desde algunas terminales
  el redibujado sale roto.
- El `.zshrc` apaga el **modo ratón** de la terminal antes de cada prompt, para evitar el ruido
  `64;46;15M…` al hacer scroll cuando un programa muere sin restaurarlo.
- El `.zshrc` anterior se respalda una vez en `~/.zshrc.pre-pi5`.

## Probado en

Raspberry Pi 5 (8 GB) con **Raspberry Pi OS (Debian 12 «bookworm»)**: pasos `tuning`, `ssh`, `shell`, `docker`,
`tailscale`, `network` y `chr` (incluido aprovisionamiento desde una imagen CHR nueva y apagado limpio).
**Debian 13 «trixie» aún no se ha probado de punta a punta**; solo se verificó que existan los repos de
Docker, Tailscale y Raspberry Pi para `trixie`. Si algo falla en trixie, abre el script: cada paso es una función.

## Seguridad

- El repositorio es **público**: este README y el script **no contienen** claves, contraseñas ni datos de tu red.
  Las claves se generan en la propia Pi (`/etc/pi5/`, solo root).
- El script se ejecuta con `sudo` y modifica `config.txt`, `cmdline.txt`, NetworkManager y SSH. Se respaldan los
  archivos de arranque (`*.pre-pi5`) y el paso `ssh` no desactiva la contraseña si no hay una llave autorizada.
- SSH escucha en todas las interfaces (cable, Wi-Fi y Tailscale) y **solo acepta llave** si hay una autorizada.
  `br0` no expone servicios nuevos de la Pi. Ojo: CHR enruta por defecto entre sus dos interfaces (no hay
  reglas de `forward` ni NAT propios); si dejas de usarlo como WAN pura, añade reglas antes.

## Pendiente

Kali (contenedor), adaptador USB wifi con modo monitor, red aislada de laboratorio, backups/snapshots del disco.
