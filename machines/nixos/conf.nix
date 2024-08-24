{ config, ... }:
let
  user = "l0lk3k";
in
{
  imports = [
    ./configuration.nix
    ./hardware-configuration.nix
    ../../modules/system/disks
    ../../modules/system/anicli-ru
    ../../modules/system/zapret
    ../../modules/system/my-services
    ../../modules/system/amdgpu
    ../../modules/system/replays
    ../../modules/system/startup-sound
    ../../modules/system/zerotier
    ../../modules/system/spicetify
  ];

  # Autologin
  services.getty.autologinUser = user;

  # Enable russian anicli
  anicli-ru.enable = true;
  
  # Enable DPI (Deep packet inspection) bypass
  zapret.enable = true;
  
  # Enable replays
  replays.enable = true;

  # Enable startup sound on PC speaker (also plays after rebuilds)
  startup-sound.enable = false;

  # Enable zerotier
  zerotier.enable = false;

  # Enable spotify with theme
  spicetify.enable = true;

  amdgpu = {

    # Enable AMDGPU stuff
    enable = true;

    # Enable OpenCL and ROCm
    pro = false;

  };

  my-services = {

    nginx = {

      # Enable nginx
      enable = true;

      # Enable my goofy website
      website.enable = true;

      # Enable nextcloud
      nextcloud.enable = false;

      # Website domain
      hostName = "sanic.space";

    };

  };

  disks = {
    
    # Enable base disks configuration (NOT RECOMMENDED TO DISABLE, DISABLING IT WILL NUKE THE SYSTEM IF THERE IS NO ANOTHER FILESYSTEM CONFIGURATION)
    enable = true;

    # Enable system compression
    compression = true;

    second-disk = {
      
      # Enable additional disk (must be btrfs)
      enable = true;

      # Enable compression on additional disk
      compression = true;

      # Filesystem label of the partition that is used for mounting
      label = "Games";

      # Which subvolume to mount
      subvol = "games";

      # Path to a place where additional disk will be mounted
      path = "/home/${user}/Games";

    };
    
    swap = {

      file = {
        
	# Enable swapfile
	enable = false;

	# Path to swapfile
	path = "/var/lib/swapfile";

	# Size of swapfile in MB
	size = 4 * 1024;

      };

      partition = {

        # Enable swap partition
	enable = false;

	# Label of swap partition
	label = "swap";

      };

    };
  
  };
}
