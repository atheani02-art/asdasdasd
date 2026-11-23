# Atheani Cyber-Hyprland (USB 8GB Edition)

Entorno portátil de **Arch Linux** diseñado desde cero para ejecutarse con persistencia real en un pendrive de **8 GB**, con estética minimalista en **Hyprland** (basada en `roscaa-stack/dotfiles`), inicio automático **sin contraseñas** para el usuario `atheani` y herramientas esenciales de ciberseguridad y uso diario.

---

## Instalación Rápida (100% Automatizada)

Arranca la ISO oficial de **Arch Linux** (`archiso`) y ejecuta:

```bash
curl -fsSL https://raw.githubusercontent.com/atheani/dotfiles/main/setup.sh -o setup.sh && bash setup.sh
```
*(Si vas a subir el script a un repositorio con otro nombre distinto a `dotfiles`, cambia solo esa palabra en el enlace).*

### ¿Qué hace el script automáticamente?
1. **Asistente Wi-Fi interactivo:** Escanea las redes cercanas, te las numera del `1` al `N` y te conecta con solo elegir el número y poner la clave.
2. **Particionado optimizado para USB:** Formatea tu pendrive en UEFI (`GPT` + `ext4` sin journal y con `noatime` para máxima velocidad y durabilidad).
3. **Cero contraseñas:** Crea el usuario `atheani` con contraseña vacía (`passwd -d`), permisos `sudo` libres y **autologin gráfico directo** a Hyprland.

---

## Programas Incluidos

* **Entorno Visual:** Hyprland, Waybar, Kitty, Rofi, SDDM, Dunst, Pywal, Zsh + Powerlevel10k.
* **Apps Diarias:** Firefox, Thunar (Explorador de archivos), Spotify, Visual Studio Code (`code`).
* **Ciberseguridad:** Nmap, Wireshark, Aircrack-ng, John the Ripper, Hydra, SQLmap, Gobuster, Nikto, Netcat, Tcpdump, Macchanger, Proxychains, Tor.

---

## Atajos de Teclado Principales

| Atajo | Acción |
| :--- | :--- |
| `Super` + `Enter` / `Q` | Abrir terminal (**Kitty**) |
| `Super` + `D` / `Espacio` | Lanzador de aplicaciones (**Rofi**) |
| `Super` + `E` | Explorador de archivos (**Thunar**) |
| `Super` + `B` | Navegador web (**Firefox**) |
| `Super` + `C` | Editor de código (**Visual Studio Code**) |
| `ImprPant` (`Print`) | Captura de pantalla con recorte y edición |
