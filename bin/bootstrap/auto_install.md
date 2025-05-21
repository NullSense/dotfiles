# chezmoi

// so you don't have to edit via chezmoi
chezmoi edit --watch $FILENAME
// Pull the latest changes from your repo and see what would change, without actually applying the changes
chezmoi git pull -- --autostash --rebase && chezmoi diff


# locale
// put into chezmoi
/etc/locale.gen
/etc/locale.conf
sudo locale-gen

# environment
// put into chezmoi
/etc/environment

# yazi:

ya pack -a bennyyip/gruvbox-dark

# clipboard win=linux
// Replace 1000 with your actual user ID if different (check with `id -u`)
sudo ln -sf /mnt/wslg/runtime-dir/wayland-0 /run/user/1000/wayland-0
sudo ln -sf /mnt/wslg/runtime-dir/wayland-0.lock /run/user/1000/wayland-0.lock

# reflector
// put into chezmoi
/etc/xdg/reflector/reflector.conf
reflector.service // start service
sudo systemctl enable --now reflector.timer
sudo systemctl start reflector.timer

# logrotate
sudo systemctl enable --now logrotate.timer
sudo systemctl start logrotate.timer

# updatedb
sudo systemctl enable --now updatedb.timer
sudo systemctl start updatedb.timer

# fstrim
// ssd periodic trim
sudo systemctl enable --now fstrim.timer
sudo systemctl start fstrim.timer

# man-db
sudo systemctl enable --now man-db.timer
sudo systemctl start man-db.timer

# pacman
// put into chezmoi
/etc/pacman.conf
// clean packages periodically
sudo systemctl enable --now paccache.timer
sudo systemctl start paccache.timer
sudo systemctl enable --now paccache

# paru
sudo pacman -S --needed base-devel
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
