# Example system for the Galaxy Tab S8: Plasma 6 as a tablet desktop. Copy it next to
# your own flake and adjust; see docs/NIXOS.md for the install.
{ lib, pkgs, ... }:

{
  hardware.samsung-gts8wifi = {
    enable = true;
    # kernelBase = "7.2";
    # After the first boot: sudo gts8wifi-firmware-setup --firmware-dir /etc/nixos/gts8wifi-firmware
    # firmware = ./gts8wifi-firmware;
    # Needed for system.build.bootImage (see docs/NIXOS.md):
    # stockRamdisk = ./stock-boot-ramdisk;
  };

  networking.hostName = "gts8wifi";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Zurich";

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };
  services.desktopManager.plasma6.enable = true;

  # No keyboard: KWin starts the Plasma on-screen keyboard and shows it for text fields
  # in tablet mode (as the pmOS package's /etc/xdg/kwinrc).
  environment.etc."xdg/kwinrc".text = ''
    [Wayland]
    InputMethod[$e]=/run/current-system/sw/share/applications/org.kde.plasma.keyboard.desktop
    VirtualKeyboardEnabled=true
  '';

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
  };

  environment.systemPackages = with pkgs; [
    kdePackages.konsole
    kdePackages.dolphin
    kdePackages.okular
    kdePackages.gwenview
    firefox
    git
  ];

  users.users.tablet = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
    # Change it on first login.
    initialPassword = "gts8wifi";
  };

  services.openssh.enable = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.11";
}
