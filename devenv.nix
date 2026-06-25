{ pkgs, ... }:

{
  packages = with pkgs; [
    xcodegen
    swift-format
    swiftlint
    prek
    protobuf
  ];

  languages.rust = {
    enable = true;
    channel = "stable";
  };

  enterShell = ''
    if git rev-parse --git-dir >/dev/null 2>&1; then
      hook_path="$(git rev-parse --git-path hooks/pre-commit)"
      if ! grep -q prek "$hook_path" 2>/dev/null; then
        echo "warning: prek git hook is not installed. Run: prek install"
      fi
    fi
  '';
}
