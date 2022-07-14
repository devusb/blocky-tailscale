{
  description = "blocky-tailscale";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: rec {

    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    blockyConfig = pkgs.writeText "blocky.cfg" ''
      port: 53
      httpPort: 4000
      upstream:
        default:
          - 1.1.1.1
      conditional:
        mapping:
          local: 192.168.20.1
          .: 192.168.20.1
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
      customDNS:
        customTTL: 1h
        mapping:
          hass.local: 192.168.10.119
          gaia.local: 192.168.20.13
          r2d2.local: 192.168.99.101
          unifi.local: 192.168.20.105
          blocky.local: 192.168.20.120
          plex.local: 192.168.20.130
          media.local: 192.168.20.130
    '';

    entrypoint = pkgs.writeShellScriptBin "entrypoint.sh" ''
      # Create the tun device path if required
      if [ ! -d /dev/net ]; then mkdir /dev/net; fi
      if [ ! -e /dev/net/tun ]; then  mknod /dev/net/tun c 10 200; fi
      
      # Wait 5s for the daemon to start and then run tailscale up to configure
      /bin/sh -c "sleep 5; ${pkgs.tailscale}/bin/tailscale up --accept-routes --accept-dns --authkey=$TAILSCALE_AUTHKEY" &
      exec ${pkgs.tailscale}/bin/tailscaled --state=/tailscale/tailscaled.state &
      ${pkgs.blocky}/bin/blocky -c ${blockyConfig}
    '';
    
    dockerImage = pkgs.dockerTools.buildImage {
      name = "blocky-tailscale";
      copyToRoot = pkgs.buildEnv {
        name = "image-root";
        pathsToLink = [ "/bin" ];
        paths = [
          pkgs.coreutils
          pkgs.bash
          pkgs.nano
          pkgs.blocky
          pkgs.tailscale
          pkgs.cacert
        ];
      };
      config.Cmd = [ "${entrypoint}/bin/entrypoint.sh" ]; 
      config.Env = [
        "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        ];
    };


  };
}
