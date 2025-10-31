{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.cape;
  kvm_config = generators.toINI { } {
    kvm = {
      # Specify a comma-separated list of available machines to be used. For each
      # specified ID you have to define a dedicated section containing the details
      # on the respective machine. (E.g. cuckoo1,cuckoo2,cuckoo3)
      machines = "win10";

      interface = "virbr0";

      # To connect to local or remote host
      dsn = "qemu:///system";
    };
    win10 = {
      label = "win10";
      platform = "windows";
      ip = "192.168.122.10";
      tags = "win10";
      snapshot = "cape_snapshot";
      interface = "virbr0";
      arch = "x64";
    };
  };
  cape_with_uv = pkgs.stdenv.mkDerivation {
    pname = "cape_with_uv";
    version = inputs.cape.rev;
    src = inputs.cape;

    # Use consistent Python package set
    nativeBuildInputs = with pkgs; [
      python312
      python312Packages.uv
      python312Packages.pip
      python312Packages.setuptools
      python312Packages.wheel
      migrate-to-uv
      rsync
      git
      gnused
      cacert
      pkg-config
      libffi
      zlib
      openssl
      findutils
    ];

    buildInputs = with pkgs; [
      graphviz
      ssdeep
    ];

    buildPhase = ''
      mkdir -p "$out"
      rsync -a --no-links ./. "$out"
      cd "$out"
      sed -i "/#.*/d" extra/optional_dependencies.txt
      export PYTHONPATH="${pkgs.python312.sitePackages}"
      export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
      export UV_PYTHON="${pkgs.python312}/bin/python"
      export HOME="$(mktemp -d)"
      export UV_NO_MANAGED_PYTHON=true
      export UV_SYSTEM_PYTHON=true
      migrate-to-uv
      uv add -r extra/optional_dependencies.txt
      uv lock
      mkdir dummy
      echo "print(\"Hello World\")" > dummy/kek.py
      echo "
      [tool.hatch.build.targets.wheel]
      packages = [
        \"dummy\"
      ]
      " >> pyproject.toml
      rm -rf .[^.]*
    '';

    dontInstall = true;
    dontFixup = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "sha256-QiWO6ZmivlegIBgY06b5eE/FmsxYURuYvhSRV6w9zP4=";
  };
  hacks = pkgs.callPackage inputs.pyproject-nix.build.hacks { };
  add_setuptools =
    final: prev: list:
    builtins.listToAttrs (
      builtins.map (x: {
        name = x;
        value = prev.${x}.overrideAttrs (old: {
          propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [ final.setuptools ];
        });
      }) list
    );
  add_from_nixpkgs =
    list:
    builtins.listToAttrs (
      builtins.map (x: {
        name = x;
        value = hacks.nixpkgsPrebuilt {
          from = pkgs.python312Packages.${x};
        };
      }) list
    );
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = cape_with_uv; };
  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
    environ = {
      sys_platform = "linux";
      os_name = "posix";
    };
  };
  python_set = pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python312; };
  overrides =
    final: prev:
    {
      bs4 = final.beautifulsoup4;
      pyattck = prev.pyattck.overrideAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
          final.poetry-core
          final.setuptools
        ];
      });
      pyattck-data = prev.pyattck.overrideAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
          final.poetry-core
          final.setuptools
        ];
      });
      pygraphviz = prev.pygraphviz.overrideAttrs (old: {
        propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
          final.poetry-core
          final.setuptools
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.graphviz ];
      });
    }
    // add_setuptools final prev [
      "django-allauth"
      "django-settings-export"
      "ida-settings"
      "intervaltree"
      "jsbeautifier"
      "setproctitle"
      "pythonaes"
      "python-tlsh"
      "netstruct"
      "httpretty"
      "func-timeout"
      "tlslite-ng"
      "xlmmacrodeobfuscator"
      "socks5man"
      "pyclamd"
      "pdfminer"
      "brotli"
      "peepdf-3"
      "httpreplay"
      "batch-deobfuscator"
    ]
    // add_from_nixpkgs [
      "libvirt"
      "certvalidator"
      "asn1crypto"
      "mscerts"
      "gunicorn"
    ];

  pySet = ((python_set.overrideScope inputs.pyproject-build-systems.overlays.wheel).overrideScope overlay).overrideScope overrides;

  cape_python_venv = pySet.mkVirtualEnv "cape_with_uv-env" (
    workspace.deps.all
    // {
      libvirt = [ ];
    }
  );
  additional_path = with pkgs; [
    git
    crudini
    findutils
    jq
    sqlite
    tmux
    net-tools
    checkinstall
    graphviz
    psmisc
    subversion
    innoextract
    msitools
    zpaq
    upx
    wget
    zip
    unzip
    lzip
    rar
    volatility3
    mitmproxy
    unrar
    # pkgs.de4dot needs packaging
    # pkgs.unace needs packaging
    cabextract
    ssdeep
    exiftool
    mono
    nfs-utils
    iptables
    privoxy
    openvpn
    wireguard-tools
    tcpdump
    wireshark
    wkhtmltopdf
    xvfb-run
    suricata
    jemalloc
    netcat
  ];
  cape-env = pkgs.stdenv.mkDerivation {
    pname = "cape-env";
    version = inputs.cape.rev;
    src = cape_with_uv;

    nativeBuildInputs = [
      pkgs.crudini
      pkgs.makeWrapper
    ];

    buildPhase = ''
            runHook preBuild
            
            cp -r conf/default/* conf/
                
            for file in conf/*.default; do
              mv -- "$file" "''${file%%.default}"
            done

            echo "${kvm_config}" > conf/kvm.conf

            substituteInPlace conf/cuckoo.conf \
              --replace-fail "connection =" "connection = postgresql:///cape"

            crudini --set conf/cuckoo.conf resultserver ip 192.168.122.1

            crudini --set conf/cuckoo.conf cuckoo machinery_screenshots on

            crudini --set conf/cuckoo.conf resultserver upload_max_size 1000000000

            crudini --set conf/cuckoo.conf processing analysis_size_limit 200000000

            crudini --set conf/cuckoo.conf cuckoo freespace 10000

            crudini --set conf/cuckoo.conf cuckoo freespace_processing 5000

            crudini --set conf/auxiliary.conf auxiliary_modules evtx yes

            crudini --set conf/auxiliary.conf auxiliary_modules procmon yes

            crudini --set conf/auxiliary.conf auxiliary_modules recentfiles yes

            crudini --set conf/auxiliary.conf auxiliary_modules usage yes

            crudini --set conf/auxiliary.conf auxiliary_modules file_pickup yes

            crudini --set conf/auxiliary.conf auxiliary_modules permissions yes

            crudini --set conf/auxiliary.conf auxiliary_modules watchdownloads yes

            crudini --set conf/auxiliary.conf auxiliary_modules screenshots_windows no

            crudini --set conf/auxiliary.conf auxiliary_modules screenshots_linux no

            crudini --set conf/auxiliary.conf QemuScreenshots enabled yes

            crudini --set conf/auxiliary.conf sniffer interface virbr0

            crudini --set conf/auxiliary.conf sniffer tcpdump /run/wrappers/bin/tcpdump-cape
            
            crudini --set conf/reporting.conf mongodb enabled yes

            crudini --set conf/routing.conf routing enable_pcap yes

            crudini --set conf/routing.conf routing internet enp2s0

            crudini --set conf/routing.conf routing reject_segments "192.168.0.0/24,10.8.1.0/24"

            crudini --set conf/routing.conf routing reject_hostports "22,80,443,631,1935,4822,5432,6463,8000,8008,27017"

            crudini --set conf/routing.conf routing route internet

            crudini --set conf/web.conf security csrf_trusted_origins "cape.sanic.space"

            crudini --set conf/routing.conf tor enabled yes

            crudini --set conf/routing.conf tor interface virbr0

            crudini --set conf/web.conf guacamole enabled yes
            
            crudini --set conf/web.conf guacamole guacd_host localhost
            
            crudini --set conf/web.conf guacamole guacd_port 4822

            crudini --set conf/web.conf general hostname "cape.sanic.space"
            
            crudini --set conf/web.conf guacamole vnc_host localhost
            
            crudini --set conf/web.conf guacamole guacd_recording_path "/var/lib/cape/guacrecordings"

            crudini --set conf/processing.conf behavior ram_boost yes

            substituteInPlace web/web/settings.py \
        --replace 'ALLOWED_HOSTS = ["*"]' \
                  'ALLOWED_HOSTS = ["*", "cape.sanic.space"]'

            substituteInPlace lib/cuckoo/core/guest.py \
              --replace-fail "from zipfile import ZIP_STORED, ZipFile" \
      "from zipfile import ZIP_STORED, ZipFile, ZipInfo
      import time
      import stat"

            substituteInPlace lib/cuckoo/core/guest.py \
              --replace-fail \
      '    for root, dirs, files in os.walk(root):
              archive_root = os.path.abspath(root)[root_len:]
              for name in files:
                  path = os.path.join(root, name)
                  archive_name = os.path.join(archive_root, name)
                  zip_file.write(path, archive_name)' \
      '    for root, dirs, files in os.walk(root):
              archive_root = os.path.abspath(root)[root_len:]
              for name in files:
                  path = os.path.join(root, name)
                  archive_name = os.path.join(archive_root, name)
                  
                  st = os.stat(path)
                  date_time = time.localtime(st.st_mtime)

                  if date_time[0] < 1980:
                      date_time = (1980, 1, 1, 0, 0, 0)

                  zinfo = ZipInfo(archive_name, date_time)
                  zinfo.external_attr = st.st_mode << 16
                  zinfo.compress_type = zip_file.compression

                  with open(path, "rb") as f:
                      zip_file.writestr(zinfo, f.read())'

            substituteInPlace web/web/settings.py \
              --replace 'DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": "siteauth.sqlite"}}' \
                        'DATABASES = {
                "default": {
                    "ENGINE": "django.db.backends.postgresql",
                    "NAME": "cape",
                    "USER": "cape",
                    "PASSWORD": "",
                    "HOST": "/var/run/postgresql",
                    "PORT": "5432",
                }
            }'

            runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R . $out/
      cp "${pkgs._7zz-rar}/bin/7zz" "$out/data/7zz"
    '';
  };
  mongoCnf =
    cfg:
    pkgs.writeText "mongodb.conf" ''
      net.bindIp: ${cfg.bind_ip}
      ${lib.optionalString cfg.quiet "systemLog.quiet: true"}
      systemLog.destination: syslog
      storage.dbPath: ${cfg.dbpath}
      ${lib.optionalString cfg.enableAuth "security.authorization: enabled"}
      ${lib.optionalString (cfg.replSetName != "") "replication.replSetName: ${cfg.replSetName}"}
      ${cfg.extraConfig}
    '';
  seabios_pkg = pkgs.seabios-qemu.overrideAttrs (
    finalAttrs: prev: {
      version = "1.16.3";
      src = pkgs.fetchFromGitHub {
        owner = "coreboot";
        repo = "seabios";
        tag = "rel-${finalAttrs.version}";
        hash = "sha256-hWemj83cxdY8p+Jhkh5GcPvI0Sy5aKYZJCsKDjHTUUk=";
      };
      postPatch = prev.postPatch + ''
        substituteInPlace src/config.h --replace-fail "Bochs" "${cfg.spoofing.bios.vendor}"
        substituteInPlace src/config.h --replace-fail "BOCHSCPU" "${cfg.spoofing.bios.cpu}"
        substituteInPlace src/config.h --replace-fail "BOCHS " "${cfg.spoofing.bios.vendor}"
        substituteInPlace src/config.h --replace-fail "BXPC" "${cfg.spoofing.motherboard.vendor}"
        substituteInPlace vgasrc/Kconfig --replace-fail "QEMU/Bochs" "${cfg.spoofing.bios.cpu2}"
        substituteInPlace vgasrc/Kconfig --replace-fail "qemu " "${cfg.spoofing.bios.space} "
        substituteInPlace src/misc.c --replace-fail "06/23/99" "${cfg.spoofing.bios.date}"
        substituteInPlace src/fw/biostables.c --replace-fail "04/01/2014" "${cfg.spoofing.bios.date2}"
        substituteInPlace src/fw/smbios.c --replace-fail "01/01/2011" "${cfg.spoofing.bios.date2}"
        # substituteInPlace src/fw/biostables.c --replace-fail '"SeaBios"' '"${cfg.spoofing.bios.vendor2}"'
        substituteInPlace src/fw/biostables.c --replace-fail '"SeaBIOS"' '"${cfg.spoofing.bios.vendor2}"'
        substituteInPlace src/hw/blockcmd.c --replace-fail '"QEMU"' '"${cfg.spoofing.disk.vendor}"'
        substituteInPlace src/fw/acpi-dsdt.dsl --replace-fail '"BXPC"' '"${cfg.spoofing.motherboard.vendor}"'
        substituteInPlace src/fw/q35-acpi-dsdt.dsl --replace-fail '"BXPC"' '"${cfg.spoofing.motherboard.vendor}"'
        substituteInPlace src/fw/ssdt-pcihp.dsl --replace-fail '"BXPC"' '"${cfg.spoofing.bios.pci}"'
        # substituteInPlace src/fw/ssdt-pcihp.dsl --replace-fail '"BXDSDT"' '"${cfg.spoofing.bios.dsdt}"'
        substituteInPlace src/fw/ssdt-proc.dsl --replace-fail '"BXPC"' '"${cfg.spoofing.bios.pci}"'
        substituteInPlace src/fw/ssdt-proc.dsl --replace-fail '"BXSSDT"' '"${cfg.spoofing.bios.ssdt}"'
        substituteInPlace src/fw/ssdt-misc.dsl --replace-fail '"BXPC"' '"${cfg.spoofing.bios.pci}"'
        substituteInPlace src/fw/ssdt-misc.dsl --replace-fail '"BXSSDTSU"' '"${cfg.spoofing.bios.ssdtsu}"'
        # substituteInPlace src/fw/ssdt-misc.dsl --replace-fail '"BXSSDTSUSP"' '"${cfg.spoofing.bios.ssdtsusp}"'
        substituteInPlace src/fw/ssdt-pcihp.dsl --replace-fail '"BXSSDTPC"' '"${cfg.spoofing.bios.ssdtpc}"'
      '';
    }
  );
  qemu_pkg = pkgs.qemu_kvm.overrideAttrs (prev: {
    buildInputs = prev.buildInputs ++ [ pkgs.cyrus_sasl ];
    postPatch = prev.postPatch + ''
      substituteInPlace hw/ide/core.c --replace-fail "QEMU HARDDISK" "${cfg.spoofing.disk.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail "QEMU HARDDISK" "${cfg.spoofing.disk.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail 's->vendor = g_strdup("QEMU");' 's->vendor = g_strdup("${cfg.spoofing.disk.vendor}");'

      substituteInPlace hw/ide/core.c --replace-fail "QEMU DVD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.dvdrom.model}"
      substituteInPlace hw/ide/atapi.c --replace-fail "QEMU DVD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.dvdrom.model}"
      substituteInPlace hw/scsi/scsi-disk.c --replace-fail "QEMU CD-ROM" "${cfg.spoofing.dvdrom.vendor} ${cfg.spoofing.dvdrom.model}"
      substituteInPlace hw/ide/atapi.c --replace-fail 'padstr8(buf + 8, 8, "QEMU");' 'padstr8(buf + 8, 8, "${cfg.spoofing.dvdrom.vendor}");'

      substituteInPlace hw/usb/dev-wacom.c --replace-fail "QEMU PenPartner tablet" "${cfg.spoofing.tablet.vendor} ${cfg.spoofing.tablet.model}"

      substituteInPlace hw/ide/core.c --replace-fail "QEMU MICRODRIVE" "${cfg.spoofing.microdrive.vendor} MICRODRIVE"

      substituteInPlace target/i386/kvm/kvm.c --replace-fail "KVMKVMKVM\\0\\0\\0" "${cfg.spoofing.hypervisor}"

      substituteInPlace block/bochs.c --replace-fail '"bochs"' '"${cfg.spoofing.disk.vendor}"'
      substituteInPlace include/hw/acpi/aml-build.h --replace-fail '"BOCHS "' '"${cfg.spoofing.acpioemid}"'

      substituteInPlace roms/ipxe/src/drivers/net/pnic.c --replace-fail "Bochs Pseudo" "${cfg.spoofing.network}"

      substituteInPlace include/hw/acpi/aml-build.h --replace-fail "BXPC" "${cfg.spoofing.motherboard.vendor}"
    '';
    configureFlags = prev.configureFlags ++ [
      "--target-list=i386-softmmu,x86_64-softmmu,i386-linux-user,x86_64-linux-user"
      "--enable-kvm"
      "--enable-gtk"
      "--enable-spice"
      "--enable-vnc"
      "--enable-vnc-sasl"
      "--enable-gnutls"
      "--enable-docs"
      "--enable-curl"
      "--enable-linux-aio"
      "--enable-cap-ng"
      "--enable-vhost-net"
      "--enable-vhost-crypto"
      "--enable-usb-redir"
      "--enable-lzo"
      "--enable-snappy"
      "--enable-bzip2"
      "--enable-coroutine-pool"
      "--enable-replication"
      "--enable-tools"
    ];
    postInstall = (prev.postInstall or "") + ''
      mkdir -p "$out/share/qemu"
      rm "$out/share/qemu/bios.bin"
      rm "$out/share/qemu/bios-256k.bin"
      cp "${seabios_pkg}/share/seabios/bios.bin" "$out/share/qemu/bios.bin"
      cp "${seabios_pkg}/share/seabios/bios.bin" "$out/share/qemu/bios-256k.bin"
      ln -s "$out/bin/qemu-system-x86_64" "$out/bin/qemu-system-x86_64-spice"
      ln -s "$out/bin/qemu-system-x86_64" "$out/bin/kvm-spice"
      ln -s "$out/bin/qemu-system-x86_64" "$out/bin/kvm"
    '';
  });
in
{
  options.cape = {
    enable = mkEnableOption "Enable CAPEv2";
    users = mkOption {
      type = types.listOf types.str;
      description = ''
        Which users should be able to use CAPEv2 and libvirtd
      '';
    };
    spoofing = {
      network = mkOption {
        type = types.str;
        default = "Realtek PCIe GbE";
        description = ''
          Network controller to spoof in CAPEv2 VM (default is Realtek PCIe GbE)
        '';
      };
      acpioemid = mkOption {
        type = types.str;
        default = "ALASKA";
        description = ''
          ACPI OEM ID to spoof in CAPEv2 VM (default is ALASKA) (Must be 6 characters long)
        '';
      };
      disk = {
        model = mkOption {
          type = types.str;
          default = "XPG GAMMIX S11 Pro";
          description = ''
            Disk model to spoof in CAPEv2 VM (default is XPG GAMMIX S11 Pro)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "ADATA";
          description = ''
            Disk vendor to spoof in CAPEv2 VM (default is ADATA)
          '';
        };
      };
      dvdrom = {
        model = mkOption {
          type = types.str;
          default = "DVD-RW DVR-219L";
          description = ''
            DVD-ROM (CD_ROM) model to spoof in CAPEv2 VM (default is DVD-RW DVR-219L)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "PIONEER";
          description = ''
            DVD-ROM (CD_ROM) vendor to spoof in CAPEv2 VM (default is PIONEER)
          '';
        };
      };
      tablet = {
        model = mkOption {
          type = types.str;
          default = "Tablet GT08";
          description = ''
            Tablet model to spoof in CAPEv2 VM (default is Tablet GT08)
          '';
        };
        vendor = mkOption {
          type = types.str;
          default = "Veikk";
          description = ''
            Tablet vendor to spoof in CAPEv2 VM (default is Veikk)
          '';
        };
      };
      microdrive.vendor = mkOption {
        type = types.str;
        default = "SanDisk";
        description = ''
          Microdrive vendor to spoof in CAPEv2 VM (default is SanDisk)
        '';
      };
      motherboard.vendor = mkOption {
        type = types.str;
        default = "ASUS";
        description = ''
          Motherboard vendor to spoof in CAPEv2 VM (default is ASUS)
        '';
      };
      hypervisor = mkOption {
        type = types.enum [
          "AuthenticAMD"
          "GenuineIntel"
        ];
        default = "AuthenticAMD";
        description = ''
          Hypervisor(?) to spoof in CAPEv2 VM (default is AuthenticAMD)
        '';
      };
      bios = {
        vendor = mkOption {
          type = types.str;
          default = "AMI";
          description = ''
            BIOS vendor to spoof in SeaBIOS (default is AMI)
          '';
        };
        vendor2 = mkOption {
          type = types.str;
          default = "AMIBios";
          description = ''
            BIOS vendor to spoof in SeaBIOS (default is AMIBios)
          '';
        };
        cpu = mkOption {
          type = types.enum [
            "INTELCPU"
            "AMDCPU"
          ];
          default = "AMDCPU";
          description = ''
            BIOS CPU to spoof in SeaBIOS (default is AMDCPU)
          '';
        };
        cpu2 = mkOption {
          type = types.enum [
            ''AMD/AMD''
            ''INTEL/INTEL''
          ];
          default = ''AMD/AMD'';
          description = ''
            BIOS CPU to spoof in SeaBIOS (default is AMD/AMD)
          '';
        };
        space = mkOption {
          type = types.enum [
            "intel"
            "amd"
          ];
          default = "amd";
          description = ''
            BIOS space(?) to spoof in SeaBIOS (default is amd)
          '';
        };
        date = mkOption {
          type = types.str;
          default = "05/14/14";
          description = ''
            BIOS update date to spoof in SeaBIOS (default is 05/14/14)
          '';
        };
        date2 = mkOption {
          type = types.str;
          default = "05/14/2014";
          description = ''
            BIOS update date to spoof in SeaBIOS (default is 05/14/2014)
          '';
        };
        pci = mkOption {
          type = types.str;
          default = "ASPC";
          description = ''
            BIOS PCI controller to spoof in SeaBIOS (default is ASPC)
          '';
        };
        dsdt = mkOption {
          type = types.str;
          default = "ASDSDT";
          description = ''
            BIOS DSDT (Differentiated System Description Table) to spoof in SeaBIOS (default is ASDSDT)
          '';
        };
        ssdtpc = mkOption {
          type = types.str;
          default = "ASSSDTPC";
          description = ''
            BIOS SSDTPC (Supplemental System Description Table PCI) to spoof in SeaBIOS (default is ASSSDTPC)
          '';
        };
        ssdt = mkOption {
          type = types.str;
          default = "ASSSDT";
          description = ''
            BIOS SSDT (Supplemental System Description Table) to spoof in SeaBIOS (default is ASSSDT)
          '';
        };
        ssdtsu = mkOption {
          type = types.str;
          default = "ASSSDTSU";
          description = ''
            BIOS SSDTSU (SSDT Startup) to spoof in SeaBIOS (default is ASSSDTSU)
          '';
        };
        ssdtsusp = mkOption {
          type = types.str;
          default = "ASSSDTSUSP";
          description = ''
            BIOS SSDTSUSP (SSDT Suspend) to spoof in SeaBIOS (default is ASSSDTSUSP)
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    virtualisation = {
      libvirtd = {
        enable = true;
        qemu = {
          package = qemu_pkg;
          swtpm.enable = true;
        };
      };
    };
    environment.systemPackages = additional_path;
    boot.kernel.sysctl = {
      "fs.file-max" = 100000;
      "net.ipv6.conf.all.disable_ipv6" = 1;
      "net.ipv6.conf.default.disable_ipv6" = 1;
      "net.ipv6.conf.lo.disable_ipv6" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.tcp_fastopen" = 3;
    };
    security = {
      wrappers.tcpdump-cape = {
        source = "${pkgs.tcpdump}/bin/tcpdump";
        group = "pcap";
        owner = "cape";
        permissions = "u+x,g+x";
        capabilities = "cap_net_raw,cap_net_admin=eip";
      };
      pam.loginLimits = [
        {
          domain = "*";
          type = "soft";
          item = "nofile";
          value = 1048576;
        }
        {
          domain = "*";
          type = "hard";
          item = "nofile";
          value = 1048576;
        }
        {
          domain = "root";
          type = "soft";
          item = "nofile";
          value = 1048576;
        }
        {
          domain = "root";
          type = "hard";
          item = "nofile";
          value = 1048576;
        }
      ];
      sudo.extraRules = [
        {
          users = [ "cape" ];
          commands = [
            {
              command = "${pkgs.tcpdump}/bin/tcpdump";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
    systemd = {
      services = {
        suricata.enable = false;
        guacamole-server.wantedBy = mkForce [ "cape.service" ];
        guac-web = {
          description = "Guacamole ASGI app for CAPE";
          wantedBy = [ "cape.service" ];
          after = [ "guacamole-server.service" "cape-prepare-env.service" ];
          wants = [ "guacamole-server.service" ];
          serviceConfig = {
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape/web";
            ExecStart = ''
              ${cape_python_venv}/bin/gunicorn --bind 127.0.0.1:8008 web.asgi \
              -t 180 -w 4 -k uvicorn.workers.UvicornWorker \
              --capture-output --enable-stdio-inheritance
            '';
            Restart = "always";
            RestartSec = "5m";
          };
        };
        cape-prepare-env = {
          path = additional_path;
          description = "Populate CAPE env on first boot";
          before = [ "cape.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart =
              let
                script = pkgs.writeShellScript "populate-folders" ''
                  mkdir -p "/var/lib/cape/guacrecordings"
                  cp -a "${cape-env}/." "/var/lib/cape"
                  touch "/var/lib/cape/web/web/secret_key.py"
                  chown -R cape:cape /var/lib/cape
                  find /var/lib/cape -type f -exec chmod 644 {} \;
                  find /var/lib/cape -type d -exec chmod 755 {} \;
                '';
              in
              "${script}";
          };
        };

        cape = {
          description = "CAPE Sandbox Service";
          path = additional_path;
          wantedBy = [ "graphical.target" ];
          after = [ "cape-prepare-env.service" "graphical.target" ];
          wants = [ "cape-rooter.service" "cape-processor.service" "cape-web.service" "cape-prepare-env.service" ];
          serviceConfig = {
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python cuckoo.py";
            Restart = "always";
            RestartSec = "5m";
            LimitNOFILE = 100000;
            TimeoutStopSec = "4m";
          };
        };

        cape-processor = {
          description = "CAPE Report Processor";
          path = additional_path;
          after = [ "cape-rooter.service" ];
          before = [ "cape-prepare-env.service" ];
          wants = [ "cape.service" "cape-prepare-env.service" ];
          serviceConfig = {
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape/utils";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python process.py -p1 auto -pt 900";
            Restart = "always";
            RestartSec = "5m";
            LimitNOFILE = 100000;
          };
        };

        cape-rooter = {
          description = "CAPE Rooter";
          path = additional_path;
          wants = [ "cape-prepare-env.service" ];
          before = [ "cape-prepare-env.service" ];
          serviceConfig = {
            User = "root";
            Group = "root";
            WorkingDirectory = "/var/lib/cape/utils";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python rooter.py --systemctl ${pkgs.systemd}/bin/systemctl --sysctl ${pkgs.sysctl}/bin/sysctl --iptables ${pkgs.iptables}/bin/iptables --iptables-save ${pkgs.iptables}/bin/iptables-save --iptables-restore ${pkgs.iptables}/bin/iptables-restore --ip ${pkgs.iproute2}/bin/ip -v -g cape";
            Restart = "always";
            RestartSec = "5m";
          };
        };

        cape-web = {
          description = "CAPE WSGI app";
          path = additional_path;
          before = [ "cape-prepare-env.service" ];
          after = [ "cape-rooter.service" ];
          wants = [ "cape-rooter.service" "cape-prepare-env.service" ];
          serviceConfig = {
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape/web";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python manage.py runserver_plus 0.0.0.0:8000 --traceback --keep-meta-shutdown";
            Restart = "always";
            RestartSec = "5m";
          };
        };

        mongodb.serviceConfig = {
          ExecStart = lib.mkForce "${pkgs.numactl}/bin/numactl --interleave=all ${pkgs.mongodb}/bin/mongod --config ${mongoCnf config.services.mongodb} --fork --pidfilepath ${config.services.mongodb.pidFile} --setParameter tcmallocReleaseRate=5.0";
          LimitNOFILE = 1048576;
          Environment = "GLIBC_TUNABLES=glibc.pthread.rseq=0";
        };

        cape-mongo-cleanup = {
          description = "CAPE MongoDB Cleanup";
          path = additional_path;
          before = [ "cape-prepare-env.service" ];
          wants = [ "cape-prepare-env.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape/utils";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python cleaners.py --delete-unused-file-data-in-mongo";
          };
        };

        cape-community-update = {
          description = "CAPE Community Signature Update";
          path = additional_path;
          before = [ "cape-prepare-env.service" ];
          wants = [ "cape-prepare-env.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "cape";
            Group = "cape";
            WorkingDirectory = "/var/lib/cape/utils";
            Environment = "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.file}/lib";
            ExecStart = "${cape_python_venv}/bin/python community.py -waf -cr";
          };
        };

        cape-tor-refresh = {
          description = "CAPE Tor Circuit Refresh";
          path = additional_path;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = ''
              ${pkgs.bash}/bin/bash -c "(echo authenticate '""'; echo signal newnym; echo quit) | ${pkgs.netcat}/bin/nc localhost 9051"
            '';
          };
        };

        tune-transparent-huge-pages = {
          description = "Tune Transparent Hugepages (THP) for MongoDB performance";
          wantedBy = [ "basic.target" ];
          before = [ "mongodb.service" ];
          serviceConfig.Type = "oneshot";
          script = ''
            echo always > /sys/kernel/mm/transparent_hugepage/enabled
            echo defer+madvise > /sys/kernel/mm/transparent_hugepage/defrag
            echo 0 > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
          '';
        };
      };
      timers = {
        cape-mongo-cleanup = {
          description = "Weekly timer for CAPE MongoDB cleanup";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Sun *-*-* 01:30:00";
            Persistent = true;
            Unit = "cape-mongo-cleanup.service";
          };
        };

        cape-community-update = {
          description = "Daily timer for CAPE community signature updates";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
            Unit = "cape-community-update.service";
          };
        };

        cape-tor-refresh = {
          description = "Hourly timer for CAPE Tor circuit refresh";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
            Unit = "cape-tor-refresh.service";
          };
        };
        suricata-update-rules = {
          description = "Hourly timer for Suricata rule updates";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };
      };
    };
    nixpkgs.config.permittedInsecurePackages = [ "checkinstall-1.6.2" ];
    services = {
      guacamole-server = {
        enable = true;
        host = "127.0.0.1";
        port = 4822;
      };
      suricata = {
        enable = true;
        settings = {
          pcap = [ { interface = "lo"; } ];
          threshold-file = "${pkgs.writeText "threshold.config" ""}";
          default-rule-path = "/var/lib/suricata/rules";
          rule-files = [ "suricata.rules" ];
          mpm-algo = "hs";
          stream = {
            reassembly.depth = 0;
            checksum-validation = "none";
          };
          netmap.checksum-checks = "no";
          pcap-file.checksum-checks = "no";
          app-layer = {
            protocols = {
              http.libhtp.default-config = {
                request-body-limit = 0;
                response-body-limit = 0;
              };
              tls.ja3-fingerprints = "yes";
            };
          };
          vars.address-groups.EXTERNAL_NET = "ANY";
          security.limit-noproc = false;
          outputs = [ { eve-log.enabled = true; } ];
          file-store.enabled = "yes";
        };
      };
      mongodb.enable = true;
      tor = {
        enable = true;
        settings = {
          RunAsDaemon = 1;
          TransPort = {
            addr = "192.168.122.1";
            port = 9040;
          };
          DNSPort = {
            addr = "192.168.122.1";
            port = 5353;
          };
          NumCPUs = 4;
          SocksTimeout = 60;
          ControlPort = 9051;
          HashedControlPassword = "16:D14CC89AD7848B8C60093105E8284A2D3AB2CF3C20D95FECA0848CFAD2";
        };
      };
      postgresql = {
        enable = true;
        ensureDatabases = [ "cape" ];
        authentication = ''
          local   all         all                 peer
          host    all         all                 127.0.0.1/32      scram-sha-256
          host    all         all                 ::1/128           scram-sha-256
        '';
        initialScript = pkgs.writeText "postgresql-init" ''
          CREATE ROLE cape WITH LOGIN;
          ALTER DATABASE cape OWNER TO cape;
          GRANT ALL PRIVILEGES ON DATABASE cape TO cape;
        '';
      };
    };
    boot.kernelModules = [ "br_netfilter" ];
    users.groups.cape = { };
    users.groups.pcap = { };
    users.users =
      builtins.listToAttrs (
        builtins.map (x: {
          name = x;
          value = {
            extraGroups = [
              "libvirtd"
              "kvm"
            ];
          };
        }) cfg.users
      )
      // {
        cape = {
          isSystemUser = true;
          group = "cape";
          createHome = true;
          home = "/var/lib/cape";
          extraGroups = [
            "systemd-journal"
            "suricata"
            "libvirtd"
            "kvm"
            "pcap"
          ];
        };
      };
  };
}
