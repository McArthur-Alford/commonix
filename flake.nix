{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { }@inputs:
    {
      generateUsers = { };
      magic = x: y: [
        x
        y
      ];
    };
}
