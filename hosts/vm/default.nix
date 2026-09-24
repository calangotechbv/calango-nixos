# A throwaway QEMU host for trying each step before it reaches real hardware.
# qemu-vm.nix supplies the disk, bootloader and filesystems, so this host needs
# no hardware-configuration.nix.
{ modulesPath, username, ... }:

{
  imports = [ (modulesPath + "/virtualisation/qemu-vm.nix") ];

  virtualisation = {
    memorySize = 8192;
    cores = 6;
    diskSize = 8192;

    # virtio-gpu with virgl: the guest's GL calls run on the host's GPU.
    # Nix's QEMU brings its own Mesa, so this works on a non-NixOS host too
    # (measured on epiphany: radeonsi loads with no extra environment).
    #
    # grab-on-hover takes the keyboard (so Super binds reach the guest's
    # Hyprland, not the host's) whenever the pointer is over the window. The
    # pointer itself never needs capturing: qemu-vm.nix adds an absolute
    # usb-tablet, and the guest's hardware cursor becomes the host cursor.
    qemu.options = [
      "-vga none"
      "-device virtio-vga-gl"
      "-display gtk,gl=on,grab-on-hover=on"
    ];
    resolution = { x = 1920; y = 1080; };
  };

  # VM only: a known password so the console login works. Real hosts must not
  # carry this.
  users.users.${username}.initialPassword = "calango";
  security.sudo.wheelNeedsPassword = false;
}
