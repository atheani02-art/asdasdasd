#!/usr/bin/env bash
# ==============================================================================
# ATHEANI ARCH-HYPRLAND AUTO-INSTALLER (100% Automatizado, Sin Contraseñas)
# ==============================================================================
set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

USER_NAME="atheani"
HOSTNAME="atheani-cyber"

clear
echo -e "${CYAN}====================================================================${NC}"
echo -e "${CYAN}        ATHEANI OS - AUTO-INSTALADOR PORTÁTIL (USB 8GB)             ${NC}"
echo -e "${CYAN}====================================================================${NC}"

# ==============================================================================
# PASO 0: ASISTENTE INTERACTIVO DE WI-FI
# ==============================================================================
conectar_wifi() {
    echo -e "${YELLOW}[*] Verificando conexión a internet...${NC}"
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        echo -e "${GREEN}[✓] ¡Conexión a internet detectada!${NC}\n"
        return 0
    fi

    echo -e "${YELLOW}[!] No hay internet. Buscando tarjeta Wi-Fi...${NC}"
    WIFI_DEV=$(iwctl device list | awk '/station/ {print $2; exit}')

    if [ -z "$WIFI_DEV" ]; then
        echo -e "${RED}[X] No se detectó tarjeta Wi-Fi. Conecta cable de red e intenta de nuevo.${NC}"
        exit 1
    fi

    echo -e "${CYAN}[*] Escaneando redes Wi-Fi disponibles en $WIFI_DEV...${NC}"
    iwctl station "$WIFI_DEV" scan
    sleep 3

    mapfile -t REDES < <(iwctl station "$WIFI_DEV" get-networks | sed -r "s/\x1B\[[0-9;]*[mK]//g" | tail -n +5 | awk '{print $1}' | grep -v "^$")

    if [ ${#REDES[@]} -eq 0 ]; then
        echo -e "${RED}[X] No se encontraron redes Wi-Fi cercanas.${NC}"
        exit 1
    fi

    echo -e "\n${CYAN}Redes Wi-Fi disponibles:${NC}"
    for i in "${!REDES[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC} ${REDES[$i]}"
    done

    echo ""
    read -p "Elige el número de tu red Wi-Fi: " NUM_RED

    if ! [[ "$NUM_RED" =~ ^[0-9]+$ ]] || [ "$NUM_RED" -lt 1 ] || [ "$NUM_RED" -gt "${#REDES[@]}" ]; then
        echo -e "${RED}[X] Selección inválida.${NC}"
        exit 1
    fi

    SSID_ELEGIDO="${REDES[$((NUM_RED-1))]}"
    read -s -p "Escribe la contraseña para '$SSID_ELEGIDO': " WIFI_PASS
    echo -e "\n${CYAN}[*] Conectando a '$SSID_ELEGIDO'...${NC}"

    iwctl --passphrase "$WIFI_PASS" station "$WIFI_DEV" connect "$SSID_ELEGIDO"
    sleep 4

    if ping -c 2 -W 4 archlinux.org &>/dev/null; then
        echo -e "${GREEN}[✓] ¡Conectado exitosamente a $SSID_ELEGIDO!${NC}\n"
    else
        echo -e "${RED}[X] No se pudo conectar. Verifica la contraseña.${NC}"
        exit 1
    fi
}

conectar_wifi

# ==============================================================================
# PASO 1: SELECCIÓN DE USB Y PARTICIONADO AUTOMÁTICO
# ==============================================================================
lsblk -d -p -n -l -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Escribe la ruta exacta de tu USB de 8GB (ej. /dev/sdb): " TARGET_DISK

if [ ! -b "$TARGET_DISK" ]; then
    echo -e "${RED}Error: El disco $TARGET_DISK no existe.${NC}"
    exit 1
fi

echo -e "${YELLOW}¡ADVERTENCIA! Se borrará TODO en $TARGET_DISK.${NC}"
read -p "Escribe 'SI' en mayúsculas para continuar: " CONFIRM
if [ "$CONFIRM" != "SI" ]; then
    echo "Instalación cancelada."
    exit 1
fi

if [[ "$TARGET_DISK" == *"nvme"* ]] || [[ "$TARGET_DISK" == *"mmcblk"* ]]; then
    PART_EFI="${TARGET_DISK}p1"
    PART_ROOT="${TARGET_DISK}p2"
else
    PART_EFI="${TARGET_DISK}1"
    PART_ROOT="${TARGET_DISK}2"
fi

echo -e "${CYAN}[1/5] Particionando y formateando $TARGET_DISK...${NC}"
wipefs -af "$TARGET_DISK"
parted -s "$TARGET_DISK" mklabel gpt
parted -s "$TARGET_DISK" mkpart "EFI" fat32 1MiB 513MiB
parted -s "$TARGET_DISK" set 1 esp on
parted -s "$TARGET_DISK" mkpart "ROOT" ext4 513MiB 100%

sleep 2
mkfs.fat -F32 "$PART_EFI"
mkfs.ext4 -F -O "^has_journal" "$PART_ROOT"

mount -o noatime "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_EFI" /mnt/boot

# ==============================================================================
# PASO 2: SISTEMA BASE ARCH LINUX
# ==============================================================================
echo -e "${CYAN}[2/5] Instalando sistema base de Arch Linux...${NC}"
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode amd-ucode \
    grub efibootmgr networkmanager git zsh curl wget nano

genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's/relatime/noatime/g' /mnt/etc/fstab

# ==============================================================================
# PASO 3: CONFIGURACIÓN INTERNA (SIN CONTRASEÑAS + HYPRLAND + APPS + CYBER)
# ==============================================================================
echo -e "${CYAN}[3/5] Configurando sistema para '$USER_NAME' sin contraseñas...${NC}"
cat << 'EOF' > /mnt/root/chroot-setup.sh
#!/usr/bin/env bash
set -e

USER_NAME="atheani"
HOSTNAME="atheani-cyber"

ln -sf /usr/share/zoneinfo/America/Caracas /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "es_VE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=es_VE.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
pacman -Syy --noconfirm

# Bootloader portátil (--removable)
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ATHEANI --removable
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Ecosistema completo estilo Archcraft + Apps diarias
pacman -S --noconfirm --needed \
    xorg-xwayland wayland wlroots \
    mesa vulkan-intel vulkan-radeon \
    hyprland waybar kitty rofi-wayland sddm swww hyprlock \
    dunst libnotify polkit-gnome xdg-desktop-portal-hyprland \
    wl-clipboard cliphist grim slurp swappy brightnessctl playerctl \
    pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol \
    bluez bluez-utils blueman network-manager-applet \
    python-pywal zsh neovim ranger fastfetch btop \
    thunar thunar-volman thunar-archive-plugin gvfs tumbler file-roller \
    firefox spotify-launcher code \
    ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts noto-fonts-emoji \
    papirus-icon-theme lxappearance

# Arsenal esencial de Ciberseguridad
pacman -S --noconfirm --needed \
    nmap wireshark-qt aircrack-ng john hydra \
    sqlmap gobuster nikto openbsd-netcat tcpdump \
    whois bind python-pip python-virtualenv \
    macchanger proxychains-ng tor

# Crear usuario atheani SIN CONTRASEÑA y con sudo libre
useradd -m -G wheel,wireshark,video,audio,storage,network -s /usr/bin/zsh "$USER_NAME"
passwd -d "$USER_NAME"
passwd -d root
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Autologin gráfico automático en SDDM sin pedir clave
mkdir -p /etc/sddm.conf.d
cat << EOL > /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER_NAME
Session=hyprland
Relogin=false
EOL

# Dotfiles visuales (roscaa-stack) + Integración
USER_HOME="/home/$USER_NAME"
git clone --depth=1 https://github.com/roscaa-stack/dotfiles.git /tmp/roscaa-dots
mkdir -p "$USER_HOME/.config" "$USER_HOME/.cache"
cp -r /tmp/roscaa-dots/.config/* "$USER_HOME/.config/" 2>/dev/null || true
cp -r /tmp/roscaa-dots/Pictures "$USER_HOME/" 2>/dev/null || true
cp -r /tmp/roscaa-dots/color-scripts "$USER_HOME/" 2>/dev/null || true
cp -r /tmp/roscaa-dots/wal "$USER_HOME/.cache/" 2>/dev/null || true
cp /tmp/roscaa-dots/.zshrc "$USER_HOME/" 2>/dev/null || true
cp /tmp/roscaa-dots/.p10k.zsh "$USER_HOME/" 2>/dev/null || true
rm -rf /tmp/roscaa-dots

sudo -u "$USER_NAME" sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' || true
sudo -u "$USER_NAME" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k" || true

# ==============================================================================
# CREAR GUÍA DE ATAJOS Y CONFIGURAR APERTURA EN EL PRIMER INICIO
# ==============================================================================
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
if [ -f "$HYPR_CONF" ]; then
    cat << 'EOL' >> "$HYPR_CONF"

# --- Integración completa estilo Archcraft ---
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
exec-once = dunst
exec-once = nm-applet --indicator
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
fi

mkdir -p "$USER_HOME/.config/gtk-3.0"
cat << 'EOL' > "$USER_HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=1
EOL

WALLPAPER=$(find "$USER_HOME/Pictures" -type f | head -n 1)
if [ -n "$WALLPAPER" ]; then
    sudo -u "$USER_NAME" wal -i "$WALLPAPER" -n || true
fi

chown -R "$USER_NAME:$USER_NAME" "$USER_HOME"

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable sddm

# Limpieza extrema para ahorrar espacio en USB 8GB
pacman -Scc --noconfirm
rm -rf /var/cache/pacman/pkg/* /tmp/*
mkdir -p /etc/systemd/journald.conf.d
echo -e "[Journal]\nSystemMaxUse=25M\nRuntimeMaxUse=10M" > /etc/systemd/journald.conf.d/size.conf
EOF

chmod +x /mnt/root/chroot-setup.sh

echo -e "${CYAN}[4/5] Ejecutando instalación completa...${NC}"
arch-chroot /mnt /root/chroot-setup.sh
rm -f /mnt/root/chroot-setup.sh

echo -e "${CYAN}[5/5] Finalizando y desmontando USB...${NC}"
umount -R /mnt

echo -e "${GREEN}====================================================================${NC}"
echo -e "${GREEN}   ¡LISTO ATHEANI! Reinicia y arranca desde tu USB de 8 GB.         ${NC}"
echo -e "${GREEN}   Usuario: atheani (Inicio automático, SIN contraseña)             ${NC}"
echo -e "${GREEN}====================================================================${NC}"
