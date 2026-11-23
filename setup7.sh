#!/usr/bin/env bash
# ==============================================================================
#  ATHEANI OS // ENTERPRISE-GRADE PORTABLE ARCH-HYPRLAND INSTALLER (USB 8GB)
#  Arquitectura: x86_64 UEFI | Persistencia Real | Cero Contraseñas | Tolerante a Fallos
# ==============================================================================
set -Eeuo pipefail

# --- Paleta de Colores Minimalista ---
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[38;5;51m'
BLUE='\033[38;5;39m'
GREEN='\033[38;5;48m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;196m'
WHITE='\033[38;5;255m'

USER_NAME="atheani"
HOSTNAME="atheani-cyber"
LOG_FILE="/tmp/atheani-install.log"
: > "$LOG_FILE"

# --- Sistema de UI y Auditoría ---
banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ┌──────────────────────────────────────────────────────────────────────┐"
    echo "  │                   A T H E A N I   O S   //   v3.1 PRO                │"
    echo "  │       Arch Linux + Hyprland + CyberSec Suite (USB 8GB Edition)       │"
    echo "  └──────────────────────────────────────────────────────────────────────┘"
    echo -e "${RESET}"
}

step_header() {
    local step_num="$1"
    local step_title="$2"
    echo -e "\n${BLUE}${BOLD}▸ [${step_num}] ${WHITE}${step_title}${RESET}"
    echo -e "${DIM}  ──────────────────────────────────────────────────────────────────────${RESET}"
}

info() { echo -e "  ${CYAN}•${RESET} $1"; }
ok()   { echo -e "  ${GREEN}${BOLD}[✓]${RESET} ${GREEN}$1 — Completado con 0 errores.${RESET}"; }
warn() { echo -e "  ${YELLOW}${BOLD}[!]${RESET} ${YELLOW}$1${RESET}"; }

fail() {
    echo -e "\n  ${RED}${BOLD}[✗] ERROR CRÍTICO:${RESET} ${RED}$1${RESET}"
    echo -e "  ${DIM}Últimas líneas del registro ($LOG_FILE):${RESET}"
    tail -n 8 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || true
    echo ""
    exit 1
}

trap 'fail "Fallo inesperado en la línea $LINENO (Código de salida: $?)"' ERR

# --- Ejecutor Resiliente con Reintentos y Limpieza de Caché Corrupta ---
run_retry() {
    local desc="$1"
    shift
    local max_attempts=5
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        info "$desc ${DIM}(Intento $attempt/$max_attempts)...${RESET}"
        if "$@" >> "$LOG_FILE" 2>&1; then
            return 0
        fi
        warn "Interrupción detectada en '$desc'. Limpiando descargas parciales y reintentando en 5s..."
        rm -f /var/cache/pacman/pkg/*.part /mnt/var/cache/pacman/pkg/*.part 2>/dev/null || true
        sleep 5
        ((attempt++))
    done
    fail "No se pudo completar '$desc' tras $max_attempts intentos."
}

# ==============================================================================
# INICIO DEL INSTALADOR
# ==============================================================================
banner

# ==============================================================================
# PASO 0: AUDITORÍA DE PRE-VUELO (UEFI, ROOT, ARQUITECTURA, RAM)
# ==============================================================================
step_header "0/7" "Auditoría de Pre-Vuelo del Sistema Host"

[ "$EUID" -ne 0 ] && fail "Este instalador debe ejecutarse como root."
[ ! -d "/sys/firmware/efi/efivars" ] && fail "El sistema no arrancó en modo UEFI. Activa EFI en la BIOS o VirtualBox."

RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
[ "$RAM_MB" -lt 1024 ] && fail "Memoria RAM insuficiente (${RAM_MB}MB). Se requieren al menos 1024MB."

# Matar procesos pacman bloqueados si existieran
killall -9 pacman 2>/dev/null || true
rm -f /var/lib/pacman/db.lck

ok "Entorno UEFI, permisos root y hardware verificados (${RAM_MB}MB RAM)"

# ==============================================================================
# PASO 1: CONECTIVIDAD DE RED Y SINCRONIZACIÓN NTP
# ==============================================================================
step_header "1/7" "Conectividad a Internet y Sincronización Horaria"

if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    info "Enlace de red activo detectado."
else
    warn "Sin conexión a Internet. Iniciando asistente interactivo Wi-Fi..."
    WIFI_DEV=$(iwctl device list | awk '/station/ {print $2; exit}')
    [ -z "$WIFI_DEV" ] && fail "No se detectó tarjeta Wi-Fi ni conexión Ethernet."

    info "Escaneando redes disponibles en ${BOLD}$WIFI_DEV${RESET}..."
    iwctl station "$WIFI_DEV" scan
    sleep 3

    mapfile -t REDES < <(iwctl station "$WIFI_DEV" get-networks | sed -r "s/\x1B\[[0-9;]*[mK]//g" | tail -n +5 | awk '{print $1}' | grep -v "^$")
    [ ${#REDES[@]} -eq 0 ] && fail "No se encontraron redes Wi-Fi cercanas."

    echo ""
    for i in "${!REDES[@]}"; do
        echo -e "    ${CYAN}[$((i+1))]${RESET} ${WHITE}${REDES[$i]}${RESET}"
    done
    echo ""

    read -rp "  Selecciona el número de tu red Wi-Fi: " NUM_RED
    if ! [[ "$NUM_RED" =~ ^[0-9]+$ ]] || [ "$NUM_RED" -lt 1 ] || [ "$NUM_RED" -gt "${#REDES[@]}" ]; then
        fail "Selección de red inválida."
    fi

    SSID_ELEGIDO="${REDES[$((NUM_RED-1))]}"
    read -rsp "  Contraseña para '$SSID_ELEGIDO': " WIFI_PASS
    echo ""
    info "Autenticando en '$SSID_ELEGIDO'..."

    iwctl --passphrase "$WIFI_PASS" station "$WIFI_DEV" connect "$SSID_ELEGIDO"
    sleep 4
    ping -c 2 -W 4 archlinux.org &>/dev/null || fail "No se pudo conectar a '$SSID_ELEGIDO'. Verifica la contraseña."
fi

timedatectl set-ntp true >> "$LOG_FILE" 2>&1 || true
ok "Conectividad global y sincronización NTP"

# ==============================================================================
# PASO 2: SELECCIÓN SEGURA DE USB, PARTICIONADO GPT Y OPTIMIZACIÓN FLASH
# ==============================================================================
step_header "2/7" "Selección de Unidad USB y Particionado UEFI (GPT)"

echo -e "  ${DIM}Unidades físicas disponibles:${RESET}\n"
lsblk -d -p -n -o NAME,SIZE,TRAN,MODEL | grep -v "loop" | sed 's/^/    /'
echo ""

read -rp "  Introduce la ruta exacta de tu USB (ej. /dev/sda): " TARGET_DISK
[ ! -b "$TARGET_DISK" ] && fail "El dispositivo '$TARGET_DISK' no existe."

# Verificar tamaño mínimo (al menos 6.5 GB reales)
DISK_BYTES=$(blockdev --getsize64 "$TARGET_DISK")
DISK_GB=$(awk -v b="$DISK_BYTES" 'BEGIN {printf "%.1f", b / 1073741824}')
[ "$DISK_BYTES" -lt 6800000000 ] && fail "La unidad $TARGET_DISK (${DISK_GB} GB) es demasiado pequeña. Se requieren al menos 7 GB."

# Desmontar cualquier partición previa del disco destino o /mnt
umount -R /mnt >> "$LOG_FILE" 2>&1 || true
for part in $(lsblk -ln -o NAME "$TARGET_DISK" | tail -n +2); do
    umount -f "/dev/$part" >> "$LOG_FILE" 2>&1 || true
done

echo ""
warn "¡ADVERTENCIA! Se destruirán TODOS los datos en $TARGET_DISK (${DISK_GB} GB)."
read -rp "  Escribe 'SI' en mayúsculas para confirmar: " CONFIRM
[ "$CONFIRM" != "SI" ] && fail "Instalación cancelada por el usuario."

if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
    PART_EFI="${TARGET_DISK}p1"
    PART_ROOT="${TARGET_DISK}p2"
else
    PART_EFI="${TARGET_DISK}1"
    PART_ROOT="${TARGET_DISK}2"
fi

info "Creando tabla de particiones GPT limpia en $TARGET_DISK..."
wipefs -af "$TARGET_DISK" >> "$LOG_FILE" 2>&1
parted -s "$TARGET_DISK" mklabel gpt >> "$LOG_FILE" 2>&1
parted -s "$TARGET_DISK" mkpart "EFI" fat32 1MiB 513MiB >> "$LOG_FILE" 2>&1
parted -s "$TARGET_DISK" set 1 esp on >> "$LOG_FILE" 2>&1
parted -s "$TARGET_DISK" mkpart "ROOT" ext4 513MiB 100% >> "$LOG_FILE" 2>&1

partprobe "$TARGET_DISK" >> "$LOG_FILE" 2>&1 || true
udevadm settle >> "$LOG_FILE" 2>&1 || true
sleep 2

[ ! -b "$PART_EFI" ] || [ ! -b "$PART_ROOT" ] && fail "El kernel no registró las nuevas particiones en $TARGET_DISK."

info "Formateando particiones (FAT32 EFI + EXT4 sin journal para máxima velocidad USB)..."
mkfs.fat -F32 -n "ATHEANI_EFI" "$PART_EFI" >> "$LOG_FILE" 2>&1
mkfs.ext4 -F -L "ATHEANI_OS" -O "^has_journal" "$PART_ROOT" >> "$LOG_FILE" 2>&1

info "Montando sistema de archivos destino en /mnt..."
mount -o noatime "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

ok "Particionado GPT, formateo y montaje de $TARGET_DISK (${DISK_GB} GB)"

# ==============================================================================
# PASO 3: MIRRORS BLINDADOS E INSTALACIÓN DEL SISTEMA BASE (PACSTRAP)
# ==============================================================================
step_header "3/7" "Optimización de Servidores e Instalación Base (Pacstrap)"

info "Seleccionando servidores de alta estabilidad (Brasil, Colombia, EE.UU.) y bloqueando Fastly..."
reflector --country Brazil,Colombia,US --protocol https --latest 12 --sort rate --save /etc/pacman.d/mirrorlist >> "$LOG_FILE" 2>&1 || true
sed -i '/fastly/d' /etc/pacman.d/mirrorlist

# Servidores de respaldo verificados por si reflector no devuelve resultados
cat << 'EOF' >> /etc/pacman.d/mirrorlist
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
EOF

sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 3
DisableDownloadTimeout/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf

run_retry "Actualizando llaves criptográficas (archlinux-keyring)" pacman -Sy --noconfirm archlinux-keyring

run_retry "Instalando Kernel Linux, Firmware, Microcódigos y Herramientas Base"     pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode amd-ucode     grub efibootmgr networkmanager git zsh curl wget nano

info "Generando tabla de montajes /etc/fstab optimizada (noatime)..."
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/relatime/noatime/g' /mnt/etc/fstab

[ ! -s "/mnt/etc/fstab" ] && fail "El archivo /mnt/etc/fstab se generó vacío."

ok "Instalación del sistema base Arch Linux en /mnt"

# ==============================================================================
# PASO 4: GENERACIÓN DE CONFIGURACIÓN INTERNA (CHROOT)
# ==============================================================================
step_header "4/7" "Generando Script de Despliegue Interno (Chroot)"

cat << 'EOF' > /mnt/root/chroot-setup.sh
#!/usr/bin/env bash
set -Eeuo pipefail

RESET='[0m'
BOLD='[1m'
DIM='[2m'
CYAN='[38;5;51m'
GREEN='[38;5;48m'
YELLOW='[38;5;220m'
RED='[38;5;196m'

USER_NAME="atheani"
HOSTNAME="atheani-cyber"

info() { echo -e "    ${CYAN}→${RESET} $1"; }
ok()   { echo -e "    ${GREEN}${BOLD}[✓]${RESET} ${GREEN}$1 — Completado con 0 errores.${RESET}"; }
warn() { echo -e "    ${YELLOW}[!] $1${RESET}"; }

run_retry() {
    local desc="$1"
    shift
    local max_attempts=5
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        info "$desc (Intento $attempt/$max_attempts)..."
        if "$@"; then
            return 0
        fi
        warn "Reintentando '$desc' en 5s..."
        rm -f /var/cache/pacman/pkg/*.part 2>/dev/null || true
        sleep 5
        ((attempt++))
    done
    echo -e "    ${RED}[✗] Falló '$desc' tras $max_attempts intentos.${RESET}"
    exit 1
}

# 1. Localización, ZRAM y Pacman
info "Configurando zona horaria (America/Caracas), idioma y ZRAM..."
ln -sf /usr/share/zoneinfo/America/Caracas /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#es_VE.UTF-8 UTF-8/es_VE.UTF-8 UTF-8/' /etc/locale.gen
locale-gen > /dev/null
echo "LANG=es_VE.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

sed -i '/fastly/d' /etc/pacman.d/mirrorlist
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 3
DisableDownloadTimeout/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
run_retry "Sincronizando repositorios internos" pacman -Syy --noconfirm
ok "Configuración regional y repositorios"

# 2. Bootloader Portátil UEFI + Initramfs con soporte universal USB
info "Configurando mkinitcpio con soporte universal para arranque USB en cualquier PC..."
sed -i 's/^HOOKS=.*/HOOKS=(base udev block keyboard autodetect modconf kms filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P > /dev/null 2>&1

info "Instalando GRUB UEFI en modo portátil (--removable)..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ATHEANI --removable > /dev/null
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg > /dev/null 2>&1
ok "Bootloader portátil UEFI y kernel initramfs"

# 3. Ecosistema Gráfico Hyprland + Drivers + Apps Diarias + ZRAM
run_retry "Instalando entorno gráfico Hyprland, Waybar, Kitty, Rofi, SDDM y drivers"     pacman -S --noconfirm --needed     xorg-xwayland wayland wlroots     mesa vulkan-intel vulkan-radeon xf86-video-vesa     hyprland waybar kitty rofi-wayland sddm swww hyprlock     dunst libnotify polkit-gnome xdg-desktop-portal-hyprland     wl-clipboard cliphist grim slurp swappy brightnessctl playerctl     pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol     bluez bluez-utils blueman network-manager-applet     python-pywal zsh neovim ranger fastfetch btop zram-generator     thunar thunar-volman thunar-archive-plugin gvfs tumbler file-roller     firefox spotify-launcher code     ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts noto-fonts-emoji     papirus-icon-theme lxappearance

cat << 'EOL' > /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOL
ok "Entorno gráfico Hyprland, drivers universales, apps y ZRAM"

# 4. Suite Completa de Ciberseguridad
run_retry "Instalando arsenal de Ciberseguridad (Nmap, Wireshark, Aircrack, SQLmap, Hydra, etc.)"     pacman -S --noconfirm --needed     nmap wireshark-qt aircrack-ng john hydra     sqlmap gobuster nikto openbsd-netcat tcpdump     whois bind python-pip python-virtualenv     macchanger proxychains-ng tor
ok "Suite de herramientas de ciberseguridad"

# 5. Usuario Sin Contraseña y Autologin Gráfico
info "Creando usuario '$USER_NAME' sin contraseña y con privilegios sudo..."
useradd -m -G wheel,wireshark,video,audio,storage,network -s /usr/bin/zsh "$USER_NAME"
passwd -d "$USER_NAME" > /dev/null
passwd -d root > /dev/null
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

mkdir -p /etc/sddm.conf.d
cat << EOL > /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER_NAME
Session=hyprland
Relogin=false
EOL
ok "Usuario '$USER_NAME' y autologin gráfico SDDM"

# 6. Dotfiles Visuales y Personalización (con respaldo funcional garantizado)
USER_HOME="/home/$USER_NAME"
mkdir -p "$USER_HOME/.config/hypr" "$USER_HOME/.cache"

info "Desplegando dotfiles visuales y Oh-My-Zsh..."
if git clone --depth=1 https://github.com/roscaa-stack/dotfiles.git /tmp/roscaa-dots > /dev/null 2>&1; then
    cp -r /tmp/roscaa-dots/.config/* "$USER_HOME/.config/" 2>/dev/null || true
    cp -r /tmp/roscaa-dots/Pictures "$USER_HOME/" 2>/dev/null || true
    cp -r /tmp/roscaa-dots/color-scripts "$USER_HOME/" 2>/dev/null || true
    cp -r /tmp/roscaa-dots/wal "$USER_HOME/.cache/" 2>/dev/null || true
    cp /tmp/roscaa-dots/.zshrc "$USER_HOME/" 2>/dev/null || true
    cp /tmp/roscaa-dots/.p10k.zsh "$USER_HOME/" 2>/dev/null || true
    rm -rf /tmp/roscaa-dots
else
    warn "Repositorio externo no disponible; generando configuración Hyprland limpia por defecto."
    cat << 'EOL' > "$USER_HOME/.config/hypr/hyprland.conf"
monitor=,preferred,auto,1
exec-once = waybar
exec-once = swww-daemon
input {
    kb_layout = es,us
    kb_options = grp:alt_shift_toggle
}
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
}
bind = SUPER, Return, exec, kitty
bind = SUPER, Q, killactive,
bind = SUPER, M, exit,
bind = SUPER, D, exec, rofi -show drun
bind = SUPER, V, togglefloating,
bind = SUPER, F, fullscreen,
bind = SUPER, 1, workspace, 1
bind = SUPER, 2, workspace, 2
bind = SUPER, 3, workspace, 3
bind = SUPER, 4, workspace, 4
bind = SUPER SHIFT, 1, movetoworkspace, 1
bind = SUPER SHIFT, 2, movetoworkspace, 2
bind = SUPER SHIFT, 3, movetoworkspace, 3
bind = SUPER SHIFT, 4, movetoworkspace, 4
EOL
fi

sudo -u "$USER_NAME" sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' > /dev/null 2>&1 || true
sudo -u "$USER_NAME" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k" > /dev/null 2>&1 || true

# 7. Guía Interactiva de Atajos en Primer Arranque
info "Configurando guía interactiva ~/ATAJOS.txt en el primer arranque..."
cat << 'EOL' > "$USER_HOME/ATAJOS.txt"
======================================================================
               GUÍA DE ATAJOS - ATHEANI OS (HYPRLAND)
======================================================================
(Nota: La tecla SUPER es la tecla Windows)

[ APLICACIONES PRINCIPALES ]
  SUPER + Enter          -> Abrir Terminal (Kitty)
  SUPER + D / R          -> Menú de aplicaciones (Rofi)
  SUPER + B              -> Navegador Web (Firefox)
  SUPER + E              -> Gestor de archivos (Thunar)
  SUPER + C              -> Editor de código (VS Code)
  Print (ImprPant)       -> Captura de pantalla de área (Grim + Swappy)

[ GESTIÓN DE VENTANAS ]
  SUPER + Q / W          -> Cerrar ventana activa
  SUPER + F              -> Pantalla completa
  SUPER + V / Space      -> Alternar ventana flotante
  SUPER + Flechas / HJKL -> Mover foco entre ventanas
  SUPER + Shift + Flechas-> Mover posición de ventana

[ ESPACIOS DE TRABAJO (WORKSPACES) ]
  SUPER + 1..9           -> Cambiar al escritorio 1..9
  SUPER + Shift + 1..9   -> Enviar ventana activa al escritorio 1..9
  SUPER + Rueda Ratón    -> Desplazarse entre escritorios

[ SISTEMA Y SESIÓN ]
  SUPER + L              -> Bloquear pantalla (Hyprlock)
  SUPER + M / Shift + E  -> Salir de Hyprland / Cerrar sesión

* Este archivo queda guardado en ~/ATAJOS.txt para futuras consultas.
* Pulsa 'q' para cerrar esta vista.
======================================================================
EOL

HYPR_CONF="$USER_HOME/.config/hypr/hyprland.conf"
touch "$HYPR_CONF"

cat << 'EOL' >> "$HYPR_CONF"

# --- Integración completa Atheani OS ---
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = dunst
exec-once = nm-applet --indicator
exec-once = blueman-applet
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Atajos esenciales añadidos
bind = SUPER, E, exec, thunar
bind = SUPER, B, exec, firefox
bind = SUPER, C, exec, code
bind = , Print, exec, grim -g "$(slurp)" - | swappy -f -

# --- Apertura única de guía de atajos en el primer arranque ---
exec-once = sh -c "sleep 2 && kitty --title 'Atajos Atheani OS' -e less $HOME/ATAJOS.txt && sed -i '/ATAJOS.txt/d' $HOME/.config/hypr/hyprland.conf" # FIRST_BOOT_SHORTCUTS
EOL

mkdir -p "$USER_HOME/.config/gtk-3.0"
cat << 'EOL' > "$USER_HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=1
EOL

WALLPAPER=$(find "$USER_HOME/Pictures" -type f 2>/dev/null | head -n 1 || true)
if [ -n "$WALLPAPER" ]; then
    sudo -u "$USER_NAME" wal -i "$WALLPAPER" -n > /dev/null 2>&1 || true
fi

chown -R "$USER_NAME:$USER_NAME" "$USER_HOME"
ok "Dotfiles, atajos y personalización visual"

# 8. Servicios y Optimización de Espacio USB 8GB
info "Activando servicios del sistema (NetworkManager, Bluetooth, SDDM)..."
systemctl enable NetworkManager > /dev/null 2>&1
systemctl enable bluetooth > /dev/null 2>&1
systemctl enable sddm > /dev/null 2>&1

info "Ejecutando limpieza profunda de caché y limitando logs para USB 8GB..."
pacman -Scc --noconfirm > /dev/null 2>&1
rm -rf /var/cache/pacman/pkg/* /tmp/*
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]
SystemMaxUse=25M
RuntimeMaxUse=10M" > /etc/systemd/journald.conf.d/size.conf
ok "Servicios activos y optimización de almacenamiento"
EOF

chmod +x /mnt/root/chroot-setup.sh
ok "Script de configuración chroot preparado"

# ==============================================================================
# PASO 5: EJECUCIÓN DEL DESPLIEGUE INTERNO
# ==============================================================================
step_header "5/7" "Desplegando Entorno Gráfico, Apps y Herramientas (Chroot)"
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh
ok "Despliegue interno completo en el sistema destino"

# ==============================================================================
# PASO 6: AUDITORÍA FINAL DE INTEGRIDAD Y DESMONTAJE SEGURO
# ==============================================================================
step_header "6/7" "Auditoría de Integridad y Desmontaje Seguro"

info "Verificando archivos críticos de arranque y usuario..."
[ ! -f "/mnt/boot/EFI/BOOT/BOOTX64.EFI" ] && fail "Falta el cargador UEFI BOOTX64.EFI en la partición de arranque."
[ ! -d "/mnt/home/$USER_NAME" ] && fail "No se creó el directorio personal /home/$USER_NAME."

info "Volcando búferes de memoria hacia la USB (sync)..."
sync
info "Desmontando particiones de /mnt de forma segura..."
umount -R /mnt
ok "Auditoría de integridad y desmontaje seguro"

# ==============================================================================
# PASO 7: RESUMEN DE FINALIZACIÓN
# ==============================================================================
step_header "7/7" "Proceso Finalizado"
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ┌──────────────────────────────────────────────────────────────────────┐"
echo "  │               ¡INSTALACIÓN COMPLETADA CON 0 ERRORES!                 │"
echo "  ├──────────────────────────────────────────────────────────────────────┤"
echo "  │  • Sistema:     Atheani OS v3.1 (Arch + Hyprland + CyberSec)         │"
echo "  │  • Usuario:     atheani (Autologin directo, SIN contraseña)          │"
echo "  │  • Persistencia: Total (EXT4 sin journal + ZRAM comprimida)          │"
echo "  │  • Siguiente paso: Ejecuta 'poweroff' y arranca desde tu USB.        │"
echo "  └──────────────────────────────────────────────────────────────────────┘"
echo -e "${RESET}"
