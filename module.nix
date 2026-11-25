defaultPackage:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.japantown-monitor;
  settingsFormat = pkgs.formats.toml { };
  configFile = settingsFormat.generate "japantown-monitor-config.toml" cfg.settings;
in
{
  options.services.japantown-monitor = {
    enable = lib.mkEnableOption "Japantown Monitor Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage.${pkgs.stdenv.hostPlatform.system};
      description = "The japantown-monitor package to use.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/japantown-monitor.env";
      description = ''
        Path to an environment file containing secrets (such as BAAQMD_AUTHKEY,
        SMTP_USERNAME, and SMTP_PASSWORD). Loaded by systemd before dropping
        privileges and never copied to the Nix store.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;

        options = {
          service = {
            cache_dir = lib.mkOption {
              type = lib.types.str;
              default = "/var/cache/japantown-monitor";
              description = "Directory used by diskcache.";
            };

            cache_expiry_in_seconds = lib.mkOption {
              type = lib.types.int;
              default = 600;
              description = "Cache expiration time in seconds.";
            };

            http_timeout_in_seconds = lib.mkOption {
              type = lib.types.int;
              default = 15;
              description = "HTTP request timeout in seconds.";
            };

            log_level = lib.mkOption {
              type = lib.types.enum [ "DEBUG" "INFO" "WARN" "WARNING" "ERROR" "CRITICAL" ];
              default = "WARN";
              description = "Logging verbosity level.";
            };

            interval = lib.mkOption {
              type = lib.types.str;
              default = "15m";
              example = "5m";
              description = "How often to run the monitor (systemd time span format).";
            };
          };

          notify = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable email notifications.";
            };

            sender_email = lib.mkOption {
              type = lib.types.str;
              default = "";
              example = "email@senderdomain.com";
              description = "Email address shown in the From header.";
            };

            sender_name = lib.mkOption {
              type = lib.types.str;
              default = "Air Monitor Service";
              description = "Display name shown in the From header.";
            };

            to = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "email@receiverdomain.com" ];
              description = "List of recipient email addresses.";
            };

            smtp_host = lib.mkOption {
              type = lib.types.str;
              default = "localhost";
              description = "SMTP server hostname.";
            };

            smtp_port = lib.mkOption {
              type = lib.types.port;
              default = 25;
              description = "SMTP server port.";
            };

            ssl = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to use SSL/TLS for SMTP connections.";
            };
          };

          valleywater = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable Valley Water monitoring.";
            };

            watershed = lib.mkOption {
              type = lib.types.str;
              default = "Guadalupe";
              description = "Valley Water watershed name to monitor.";
            };

            station_ids = lib.mkOption {
              type = lib.types.listOf lib.types.int;
              default = [ ];
              example = [ 12 54 ];
              description = "List of Valley Water station IDs to monitor.";
            };
          };

          baaqmd = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to enable BAAQMD air quality monitoring.";
            };

            zones = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    example = "Santa Clara Valley";
                    description = "Human-readable name of the BAAQMD zone.";
                  };

                  station_ids = lib.mkOption {
                    type = lib.types.listOf lib.types.int;
                    default = [ ];
                    example = [ 7032 ];
                    description = "List of BAAQMD station IDs in this zone.";
                  };

                  alert_level = lib.mkOption {
                    type = lib.types.int;
                    default = 51;
                    description = "AQI threshold for triggering alerts in this zone.";
                  };
                };
              });
              default = [ ];
              description = "List of BAAQMD air quality zones.";
            };
          };
        };
      };
      default = { };
      description = ''
        Configuration written to the TOML file passed to japantown-monitor.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.jtp-monitor = {
      isSystemUser = true;
      group = "jtp-monitor";
      description = "Service user for japantown-monitor";
    };
    users.groups.jtp-monitor = { };

    systemd.services."japantown-monitor" = {
      description = "Japantown Monitor Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "jtp-monitor";
        Group = "jtp-monitor";
        CacheDirectory = "japantown-monitor";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
        ExecStart = "${cfg.package}/bin/japantown-monitor --config ${configFile}";

        # Filesystem & Privilege Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;

        # Kernel & Syscall Hardening
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        SystemCallFilter = [ "@system-service" "@network-io" "@signal" ];
        SystemCallErrorNumber = "EPERM";
      };
    };

    systemd.timers."japantown-monitor" = {
      description = "Periodic timer for Japantown Monitor";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.settings.service.interval;
        OnUnitActiveSec = cfg.settings.service.interval;
        Unit = "japantown-monitor.service";
      };
    };
  };
}
