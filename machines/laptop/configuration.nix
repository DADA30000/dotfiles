{
  user,
  pkgs,
  user-hash,
  config,
  ...
}:
{
  graphics.nvidia.enable = true;
  amd-ai.enable = false;
  nix-mineral.settings.kernel.intel-iommu = false;

  home-manager.users.${user} = import ./home.nix;

  # Rebinding that special GIMATE key on my laptop to a useful sysrq/print key.
  services.udev.extraHwdb = ''
    evdev:input:b0003v*
     KEYBOARD_KEY_70067=sysrq
  '';

  disks = {
    encryption = true;
    ssdOptimizations = true;
    autoScanZfs = true;
  };

  my-services = {
    cloudflare-ddns.enable = true;
    nginx = {
      enable = true;
      website.enable = true;
    };
  };

  boot = {
    kernelParams = [ "rd.shell=0" ];
    lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
    initrd = {
      kernelModules = [
        "evdev"
        "soc_button_array"
        "gpio_keys"
      ];
      systemd.services = {
        initrd-power-button =
          let
            powerListener = pkgs.runCommandCC "initrd-power-listener" { } ''
              mkdir -p $out/bin
              cat << "C_SRC" > main.c
              #include <stdio.h>
              #include <string.h>
              #include <unistd.h>
              #include <fcntl.h>
              #include <poll.h>
              #include <sys/inotify.h>
              #include <linux/input.h>
              #include <sys/reboot.h>
              #include <glob.h>

              #define MAX_FDS 32

              static struct pollfd fds[MAX_FDS];
              static int nfds = 0;

              static void add_node(const char *path) {
                if (nfds >= MAX_FDS) return;
                int fd = open(path, O_RDONLY | O_NONBLOCK);
                if (fd >= 0) {
                  fds[nfds].fd = fd;
                  fds[nfds].events = POLLIN;
                  nfds++;
                }
              }

              static void scan_nodes(void) {
                glob_t g;
                if (glob("/dev/input/event*", 0, NULL, &g) == 0) {
                  for (size_t i = 0; i < g.gl_pathc; i++) add_node(g.gl_pathv[i]);
                  globfree(&g);
                }
              }

              int main(void) {
                int ifd = inotify_init1(IN_NONBLOCK);
                if (ifd >= 0) {
                  fds[nfds].fd = ifd;
                  fds[nfds].events = POLLIN;
                  nfds++;
                }

                int dev_wd = inotify_add_watch(ifd, "/dev", IN_CREATE);
                int input_wd = inotify_add_watch(ifd, "/dev/input", IN_CREATE);
                if (input_wd >= 0) scan_nodes();

                struct input_event ev;
                char ibuf[1024];

                while (poll(fds, nfds, -1) > 0) {
                  for (int i = 0; i < nfds; i++) {
                    if (!(fds[i].revents & POLLIN)) continue;

                    if (fds[i].fd == ifd) {
                      ssize_t len = read(ifd, ibuf, sizeof(ibuf));
                      int off = 0;
                      while (off < len) {
                        struct inotify_event *ie = (struct inotify_event *)&ibuf[off];
                        if (ie->wd == dev_wd && (ie->mask & IN_ISDIR) && !strcmp(ie->name, "input")) {
                          if (input_wd < 0) {
                            input_wd = inotify_add_watch(ifd, "/dev/input", IN_CREATE);
                            scan_nodes();
                          }
                        } else if (ie->wd == input_wd && !strncmp(ie->name, "event", 5)) {
                          char p[64];
                          snprintf(p, sizeof(p), "/dev/input/%s", ie->name);
                          add_node(p);
                        }
                        off += sizeof(struct inotify_event) + ie->len;
                      }
                    } else {
                      while (read(fds[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
                        if (ev.type == 1 && (ev.code == 116 || ev.code == 142 || ev.code == 143 || ev.code == 408) && ev.value == 1) {
                          sync();
                          reboot(0x01234567);
                        }
                      }
                    }
                  }
                }
                return 0;
              }
              C_SRC
              $CC -O2 main.c -o $out/bin/initrd-power-listener
            '';
          in
          {
            description = "Reboot on Power Button press in initrd";
            wantedBy = [ "basic.target" ];
            unitConfig = {
              DefaultDependencies = false;
              IgnoreOnIsolate = true;
            };

            serviceConfig = {
              Type = "simple";
              Restart = "no";
            };

            path = [ powerListener ];

            script = ''
              exec initrd-power-listener
            '';
          };
        pcr-gatekeeper =
          let
            luksUnits = map (n: "systemd-cryptsetup@${n}.service") (
              builtins.attrNames config.boot.initrd.luks.devices
            );
          in
          {
            wantedBy = [ "initrd.target" ];
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";

            before = [ "cryptsetup-pre.target" ] ++ luksUnits;
            requiredBy = luksUnits;
            after = [
              "plymouth-start.service"
              "dev-tpmrm0.device"
            ];

            path = [
              pkgs.mkpasswd
              pkgs.coreutils
              pkgs.tpm2-tools
              config.boot.plymouth.package
              config.boot.initrd.systemd.package
            ];

            script = ''
              export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
              EXPECTED='${user-hash}'
              SALT=$(echo "$EXPECTED" | cut -d'$' -f1-4)\$
              PCRS="0 1 2 3 5 7"

              desc() {
                case $1 in
                  0) echo "Core UEFI BIOS firmware" ;;
                  1) echo "BIOS platform & config" ;;
                  2) echo "PCIe Option ROM code" ;;
                  3) echo "PCIe hardware device config" ;;
                  5) echo "GPT partition table layout" ;;
                  7) echo "Secure Boot certificate policy" ;;
                esac
              }

              FAILED=""
              for pcr in $PCRS; do
                NV="0x150002$pcr"
                if ! tpm2_nvread -s 2 -P "pcr:sha256:$pcr" "$NV" >/dev/null 2>&1; then
                  FAILED="$FAILED $pcr"
                fi
              done

              if [ -z "$FAILED" ]; then
                exit 0
              fi

              FAILED="''${FAILED# }"
              SUMMARY="''${FAILED// /, }"

              for pcr in $FAILED; do
                plymouth message --text="PCR $pcr changed: $(desc "$pcr")"
              done

              for try in 1 2 3; do
                PASS=$(plymouth ask-for-password --prompt="PCR ($SUMMARY) changed. Key ($try/3):")
                COMPUTED=$(echo -n "$PASS" | mkpasswd -m yescrypt -s -S "$SALT" 2>/dev/null || true)
                if [ -n "$COMPUTED" ] && [ "$COMPUTED" = "$EXPECTED" ]; then
                  plymouth message --text="Re-enrolling PCR ($SUMMARY)..."
                  tpm2_nvundefine -C o 0x1500016 2>/dev/null || true
                  for pcr in $FAILED; do
                    NV="0x150002$pcr"
                    tpm2_nvundefine -C o "$NV" 2>/dev/null || true
                    tpm2_createpolicy --policy-pcr -l "sha256:$pcr" -L /tmp/p.dat >/dev/null
                    tpm2_nvdefine -C o -s 2 -a "policyread|ownerwrite" -L /tmp/p.dat "$NV" >/dev/null
                    echo -n "OK" | tpm2_nvwrite -C o -i - "$NV" >/dev/null
                    rm -f /tmp/p.dat
                  done
                  exit 0
                elif [ "$try" -lt 3 ]; then
                  plymouth message --text="Incorrect attempt $try. Retrying..."
                else
                  plymouth message --text="Lockout! Powering off..."
                  sleep 2
                  systemctl poweroff -ff
                fi
              done
            '';
          };
      };
    };
  };
}
