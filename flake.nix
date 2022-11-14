{
  description = "blocky-tailscale";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {

    blocky-tailscale =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;

        blockyConfig = pkgs.writeText "blocky.cfg" ''
          port: 53
          httpPort: 4000
          upstream:
            default:
              - 127.0.0.1:5353
          prometheus:
            enable: true
          blocking:
            blackLists:
              ads:
                - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
              smart_home:
                - |
                  n-devs.tplinkcloud.com
                  n-deventry.tplinkcloud.com
            clientGroupsBlock:
              default:
                - ads
                - smart_home
        '';

        unboundConfig = pkgs.writeText "unbound.conf" ''
          server:
          # can be uncommented if you do not need user privilige protection
          username: ""

          # can be uncommented if you do not need file access protection
          chroot: ""

          # send minimal amount of information to upstream servers to enhance privacy
          qname-minimisation: yes

          # specify the interface to answer queries from by ip-address.
          interface: 0.0.0.0
          port: 5353
          # interface: ::0

          # addresses from the IP range that are allowed to connect to the resolver
          access-control: 127.0.0.0/8 allow
          # access-control: 2001:DB8/64 allow

          #logfile
          logfile: /dev/stdout
          use-syslog: no
          log-queries: no
        '';

        nginxConfig = pkgs.writeText "nginx.conf" ''
          user nobody nobody;
          daemon off;
          error_log /dev/stdout info;
          pid /dev/null;
          events {}
          http {
            server {
                listen 80;
                listen [::]:80;
            
                location = /dns-query {
                  deny all;
                }
                location /dns-query {
                  proxy_pass http://localhost:4000/dns-query;
                }
                location / {
                  deny all;
                }
            }
          }
        '';

        entrypoint = pkgs.writeShellScriptBin "entrypoint.sh" ''
          # Create the tun device path if required
          if [ ! -d /dev/net ]; then mkdir /dev/net; fi
          if [ ! -e /dev/net/tun ]; then  mknod /dev/net/tun c 10 200; fi
      
          # Wait 5s for the daemon to start and then run tailscale up to configure
          /bin/sh -c "${pkgs.coreutils}/bin/sleep 5; ${pkgs.tailscale}/bin/tailscale up --accept-routes --accept-dns --authkey=$TAILSCALE_AUTHKEY" &
          exec ${pkgs.tailscale}/bin/tailscaled --state=/tailscale/tailscaled.state &
          ${pkgs.unbound}/bin/unbound -d -p -c ${unboundConfig} &
          ${pkgs.blocky}/bin/blocky -c ${blockyConfig} &
          ${pkgs.nginx}/bin/nginx -c ${nginxConfig}
        '';
      in
      pkgs.dockerTools.buildLayeredImage {
        name = "blocky-tailscale";
        contents = with pkgs; [
          coreutils
          blocky
          tailscale
          cacert
          unbound
          nginx
          fakeNss
        ];
        config.Cmd = [ "${entrypoint}/bin/entrypoint.sh" ];
        config.Env = [
          "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        ];
        extraCommands = ''
          # nginx still tries to read this directory even if error_log
          # directive is specifying another file :/
          mkdir -p var/log/nginx
          mkdir -p var/cache/nginx
        '';
      };
  };
}
