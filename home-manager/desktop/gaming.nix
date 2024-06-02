{ ... }:
{
  programs.mangohud = {
    enable = true;
    enableSessionWide = true;
    settings = {
      cpu_temp = 1;
      gpu_temp = 1;
      fsr = 1;
      hdr = 1;
      gamemode = 1;
      gpu_fan = 1;
      arch = 1;
      ram = 1;
      vram = 1;
      swap = 1;
      wine = 1;
    };
  };
}
