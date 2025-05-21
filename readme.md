# Dots

Arch Linux running Wayland, managed by Chezmoi.

*   **Font**: [Hack Nerd Font](https://www.nerdfonts.com/font-downloads) (for icons)
*   **Color Scheme**: Gruvbox

## I. Main Programs & Configurations

This repository includes configurations for a variety of programs. The `bootstrap.sh` script aims to install these. Key programs include:

*   **Shell**: [Zsh](https://www.zsh.org/) with zplug
*   **Terminal Emulator**: [Alacritty](https://alacritty.org/)
*   **Text Editor**: [Neovim](https://neovim.io/) (extensively configured)
*   **Wayland Compositor**: [Sway](https://swaywm.org/)
*   **Status Bar**: [Waybar](https://github.com/Alexays/Waybar) (for Sway)
*   **Application Launcher**: [sway-launcher-desktop](https://github.com/Biont/sway-launcher-desktop)
*   **File Manager (Terminal)**: [yazi](https://github.com/sxyazi/yazi) (Terminal file manager)
*   **Fuzzy Finder**: [fzf](https://github.com/junegunn/fzf)
*   **PDF Viewer**: [Zathura](https://pwmt.org/projects/zathura/)
*   **Notification Daemon**: [dunst](https://github.com/dunst-project/dunst)
*   **Screen Locker**: `swaylock` with a custom pixelation script

## II. Setup on a Fresh System

1.  **Prerequisites:**
    *   Ensure `git` and `chezmoi` are installed.
        ```
        sudo pacman -S git chezmoi
        ```

2.  **Initialize Chezmoi with this Repository:**
    This command will clone the dotfiles into `~/.local/share/chezmoi` and generate an initial configuration file.
    ```

    chezmoi init https://github.com/NullSense/dotfiles.git

    ```

3.  **Apply Dotfiles:**
    Apply the configurations to your home directory. `chezmoi apply` will create symlinks, copy files, run initialization scripts (`run_` scripts), and manage external files (e.g., plugin managers via `.chezmoiexternal.toml` if used).
    ```
    chezmoi apply
    ```

4.  **Run bootstrap script:**

    This script handles the installation of essential packages and performs other system setup tasks.
    ```
    ~/bin/bootstrap/bootstrap.sh
    ```

