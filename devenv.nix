{ pkgs, ... }:

{
  # Xcode (xcodebuild, swift, codesign, security) comes from the system
  # Xcode install — it is not available in nixpkgs on darwin. devenv
  # provides auxiliary tooling: lint/format for pre-commit hooks and
  # protoc for Packages/ArcBoxClient/generate.sh.
  packages = with pkgs; [
    xcodegen
    swift-format
    swiftlint
    pre-commit
    protobuf
  ];
}
