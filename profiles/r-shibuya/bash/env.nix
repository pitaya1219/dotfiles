{
  PATH = "~/.nix-profile/bin:/opt/homebrew/bin:/opt/homebrew/sbin:$(brew --prefix openssl)/bin:/applications/xcode.app/contents/developer/usr/bin:$PATH";
  REQUESTS_CA_BUNDLE = "/library/application support/netskope/stagent/data/nscacert_combined.pem";
  AWS_CA_BUNDLE = "$REQUESTS_CA_BUNDLE";
  GIT_SSL_CAPATH = "$REQUESTS_CA_BUNDLE";
  NODE_EXTRA_CA_CERTS = "$REQUESTS_CA_BUNDLE";
  CURL_CA_BUNDLE = "$REQUESTS_CA_BUNDLE";
  HEX_CACERTS_PATH = "$REQUESTS_CA_BUNDLE";
  NIX_SSL_CERT_FILE = "$REQUESTS_CA_BUNDLE";
  BASH_SILENCE_DEPRECATION_WARNING = 1;
  LDFLAGS = "-L/opt/homebrew/opt/mysql-client/lib";
  CPPFLAGS = "-I/opt/homebrew/opt/mysql-client/include";
  PKG_CONFIG_PATH = "/opt/homebrew/opt/mysql-client/lib/pkgconfig";
  NODE_OPTIONS = "--openssl-legacy-provider";
}
