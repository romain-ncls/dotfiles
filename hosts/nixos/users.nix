{ pkgs, ... }:
{
  users.users.romain = {
    isNormalUser = true;
    description = "Romain";
    shell = pkgs.fish;
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    # packages = with pkgs; [
    # ];
  };
  security.pki.certificates = [
    # /home/romain/.local/share/mkcert/rootCA.pem
    ''
      -----BEGIN CERTIFICATE-----
      MIIEnTCCAwWgAwIBAgIQZIvoWeZDt2dbUanoI1JVDzANBgkqhkiG9w0BAQsFADBn
      MR4wHAYDVQQKExVta2NlcnQgZGV2ZWxvcG1lbnQgQ0ExHjAcBgNVBAsMFXJvbWFp
      bkBuaXhvcyAoUm9tYWluKTElMCMGA1UEAwwcbWtjZXJ0IHJvbWFpbkBuaXhvcyAo
      Um9tYWluKTAeFw0yNjAxMjYxNDE1MDBaFw0zNjAxMjYxNDE1MDBaMGcxHjAcBgNV
      BAoTFW1rY2VydCBkZXZlbG9wbWVudCBDQTEeMBwGA1UECwwVcm9tYWluQG5peG9z
      IChSb21haW4pMSUwIwYDVQQDDBxta2NlcnQgcm9tYWluQG5peG9zIChSb21haW4p
      MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA4KeRAI5dBdxOn+m89DsZ
      vrAOL95JRiVdC6dSu2zUNQaRJZLVC3pSQmfcS4LIezTHnDORVvMZH8Cke8/FsEWQ
      YKUDHUQfn/fYCgzm04JlIaiPikXPK49oSwFKLsFxC37dS81k0Eqvv5E9cFgw2P8n
      7YB1seXpHmuqp7qzX8NTdEKJg35O0MdtnTzho/jm8aSTRDqtpBqSyQpuX5paesHP
      IX135B9aNXBy9S9WYXSBY+ytcmysCm85RDGuwo8Se+aJk7qpVtWVXNcebRFLsGeS
      ditCkQU18Mg9wm+6vwaUTghN30+n4rc8ejNt77jx45kQqlOxXC9Wi1zA1Lj9ceuT
      jTifncKXHii32RaOG51RZDwpaTu8iQtg6zaVPvSjKCNa31BX7r+VbdsLmU2dw9g/
      lXGd0LayOfq76eFSQOoMBQOWcWkdVJuyc36TjaHwqgUgabTT0qTd3il+enrpvIPd
      oHKoRZ1OGK/0AiIHoxVONb29qT2zmYuLfQvMwmT7TDhDAgMBAAGjRTBDMA4GA1Ud
      DwEB/wQEAwICBDASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBR8baCBNUZF
      PiNAhe4As8hzFydPNjANBgkqhkiG9w0BAQsFAAOCAYEAOYMv9RIACGHLaWQlEJIX
      cviUxj/UZixGMXLOwC2Ie27YmnjTD2gYhHld+FpTUG/IQnIRDFNs+zXaI5uxGugv
      6VMysmiOU12sb1bE7OmYfyiBh6/eiGQwrYU+EAn6H+ans9mTrU8HlPFWkic8wjnQ
      BhhREYJGKaWr7UOFCHKZqbscriLiARwDN0vWJhPZ+7QUTkVZwV69ABHIVAqFVXEi
      Tko0eKlNIMZVAw739mx5hdaeT3a6NblP7D0ExPiyPsRWMq86T+Y+zvnqx1Trp6C0
      fgs/6svksSaDk7Anxbha8KsU5eArzNwOwpA5ZaEUH4nMlB5vPsFUaPsr/WA7CznQ
      a5rBLaBgk6Tzq+f1ATUrF83MJFNDmzhDX+Ghc9vDoav0vVmtv6FcNWKoWCWvDcc2
      GdymcD3YG4BcuhTlWl1/RCiYp2XQaKCHsSV9zWxjS0SxxiwuvhmSFuzl34X6YWUb
      IWbgnYZEo5yxYcNZsgikXaaSUur1G28SBAPZHHK8IHm1
      -----END CERTIFICATE-----
    ''
  ];
}
