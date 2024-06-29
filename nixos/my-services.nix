{
  services.nextcloud = {
    enable = true;
    configureRedis = true;
    config.adminpassFile = "/password";
    https = true;
    hostName = "nc.akff-sanic.ru";
    package = pkgs.nextcloud29;
  };
  services.nginx = {
  enable = true;
    virtualHosts = {
      ${config.services.nextcloud.hostName} = {
        forceSSL = true;
        enableACME = true;
      };
      "akff-sanic.ru" = {
        forceSSL = true;
        enableACME = true;
        root = "/fileserver";
        extraConfig = ''
          autoindex on;
          add_before_body /.theme/header.html;
          add_after_body /.theme/footer.html; 
          autoindex_exact_size off;
        '';
      };
      "ip.akff-sanic.ru" = {
        forceSSL = true;
        enableACME = true;
        root = "/fileserver";
        extraConfig = ''
          autoindex on;
          add_before_body /.theme/header.html;
          add_after_body /.theme/footer.html; 
          autoindex_exact_size off;
        '';
      };
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "vadimhack.ru@gmail.com";
    certs = { 
      ${config.services.nextcloud.hostName}.email = "vadimhack.ru@gmail.com"; 
    };
  }; 
}
