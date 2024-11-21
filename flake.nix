{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/unstable";
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
