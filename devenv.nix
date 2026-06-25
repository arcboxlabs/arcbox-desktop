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
}
