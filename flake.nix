{
  description = "Japantown Monitor Python service and NixOS module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      defaultPackages = forAllSystems (system:
        (pkgsFor system).python3Packages.callPackage ./package.nix { }
      );
    in
    {
      packages = forAllSystems (system: {
        default = defaultPackages.${system};
      });

      nixosModules.default = import ./module.nix defaultPackages;
      # Automated NixOS VM integration test (Linux only)
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
        let
          pkgs = pkgsFor system;
        in
        {
          module-config-test = pkgs.testers.runNixOSTest {
            name = "japantown-monitor-config-test";

            nodes.machine = { ... }: {
              imports = [ self.nixosModules.default ];

              # Create a dummy secrets file inside the test VM
              environment.etc."test-secrets.env".text = ''
                BAAQMD_AUTHKEY=test_secret_key
                SMTP_USERNAME=test_user
                SMTP_PASSWORD=test_pass
              '';

              # Enable your module with custom options
              services.japantown-monitor = {
                enable = true;
                environmentFile = "/etc/test-secrets.env";

                settings = {
                  service = {
                    cache_expiry_in_seconds = 1200;
                    http_timeout_in_seconds = 30;
                    log_level = "DEBUG";
                    interval = "10m";
                  };

                  notify = {
                    enable = true;
                    sender_email = "test@senderdomain.com";
                    sender_name = "Test Monitor";
                    to = [ "test@receiverdomain.com" ];
                    smtp_host = "example.com";
                    smtp_port = 587;
                    ssl = true;
                  };

                  valleywater = {
                    enable = true;
                    watershed = "Guadalupe";
                    station_ids = [ 12 54 ];
                  };

                  baaqmd = {
                    enable = true;
                    zones = [
                      {
                        name = "Santa Clara Valley";
                        station_ids = [ 7032 ];
                        alert_level = 75;
                      }
                    ];
                  };
                };
              };
            };

            testScript = ''
              machine.wait_for_unit("multi-user.target")

              # 1. Verify the timer is active
              machine.succeed("systemctl is-active japantown-monitor.timer")

              # 2. Extract the generated --config path from the systemd unit
              exec_start = machine.succeed("systemctl show -p ExecStart --value japantown-monitor.service").strip()
              print("ExecStart:", exec_start)

              # Parse the path after '--config '
              config_path = exec_start.split("--config ")[1].split()[0].rstrip(";")
              config_content = machine.succeed(f"cat {config_path}")
              print("=== GENERATED CONFIG.TOML ===")
              print(config_content)
              print("=============================")

              # 3. Assert your Nix options rendered properly in the TOML file
              assert "cache_expiry_in_seconds = 1200" in config_content
              assert "http_timeout_in_seconds = 30" in config_content
              assert 'log_level = "DEBUG"' in config_content
              assert 'sender_email = "test@senderdomain.com"' in config_content
              assert "station_ids = [12, 54]" in config_content
              assert 'name = "Santa Clara Valley"' in config_content
              assert "alert_level = 75" in config_content

              # 4. Ensure secrets were NOT leaked into the Nix store TOML
              assert "test_secret_key" not in config_content
              assert "test_pass" not in config_content
            '';
          };
        }
      );
    };
}
