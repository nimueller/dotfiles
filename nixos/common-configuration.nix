{ config, pkgs, lib, hostname, username, ... }:
{
    nix.settings.experimental-features = [
        "nix-command"
        "flakes"
    ];
    system.stateVersion = "23.05";

    # Boot Loader
    boot.loader.timeout = 0;
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.supportedFilesystems = [ "ntfs" ];

    # Time zone and locale settings
    time.timeZone = "Europe/Berlin";
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
        LC_ADDRESS = "de_DE.UTF-8";
        LC_IDENTIFICATION = "de_DE.UTF-8";
        LC_MEASUREMENT = "de_DE.UTF-8";
        LC_MONETARY = "de_DE.UTF-8";
        LC_NAME = "de_DE.UTF-8";
        LC_NUMERIC = "de_DE.UTF-8";
        LC_PAPER = "de_DE.UTF-8";
        LC_TELEPHONE = "de_DE.UTF-8";
        LC_TIME = "de_DE.UTF-8";
    };

    # Networking
    networking.hostName = hostname;
    networking.networkmanager.enable = true;
    networking.firewall.enable = false;

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    # Enable ZSH
    programs.zsh.enable = true;

    # Used to enable completion for system packages in ZSH
    environment.pathsToLink = [ "/share/zsh" ];

    # Enable CUPS to print documents.
    services.printing.enable = true;

    # Enable sound with pipewire.
    sound.enable = false;
    hardware.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        # If you want to use JACK applications, uncomment this
        jack.enable = true;

        # use the example session manager (no others are packaged yet so this is enabled by default,
        # no need to redefine it in your config for now)
        #media-session.enable = true;
    };

    programs.command-not-found.enable = true;

    environment.systemPackages = with pkgs; [
        # Some core programs
        jq
        unzip
        git
        wget

        # Development
        gcc
        gdb
        jdk21
        python3Full
        nodejs_latest
        cargo
        gradle
        maven

        # CLI programs
        neovim
        btop
        tree

    ];

    users.users.${username} = {
        shell = pkgs.zsh;
        isNormalUser = true;
        description = username;
        extraGroups = [ "networkmanager" "wheel" ];
    };
}
