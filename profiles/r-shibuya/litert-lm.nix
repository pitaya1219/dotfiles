{ python3Packages, fetchurl }:

# nixpkgs has no LiteRT-LM, and the native runtime is only published as
# prebuilt wheels, so all three come straight from PyPI and have to move
# together: litert-lm pins the other two to its own version.
let
  version = "0.19.2";

  wheel = { pname, file, hash, dependencies ? [ ] }:
    python3Packages.buildPythonPackage {
      inherit pname version dependencies;
      format = "wheel";
      src = fetchurl {
        url = "https://files.pythonhosted.org/packages/${file}";
        inherit hash;
      };
    };

  litert-lm-api = wheel {
    pname = "litert-lm-api";
    file = "7c/29/489d33e8f8de497fb0b019ef38e44a79a3cc60933ed975a690d9a301d4bf/litert_lm_api-${version}-py3-none-macosx_12_0_arm64.whl";
    hash = "sha256-cz+uje0jQe6OilEjy5d7taPduFVYLoPG3ia07YlTPUY=";
  };

  litert-lm-builder = wheel {
    pname = "litert-lm-builder";
    file = "ce/b9/d960757b0c1fe3d0a460ee07746f3eab06d280b0d989db4faf8b58b89905/litert_lm_builder-${version}-py3-none-any.whl";
    hash = "sha256-aqWbGYnDrxicVdVTpW3Ubpx78W7c7qCWyzePPFww9/Q=";
    dependencies = with python3Packages; [ protobuf flatbuffers absl-py tomli numpy ];
  };
in
python3Packages.buildPythonApplication {
  pname = "litert-lm";
  inherit version;
  format = "wheel";
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/12/55/fda1320580b6b80a42dff0428449e5d202670cafdadd2c02aed0a007d15f/litert_lm-${version}-py3-none-any.whl";
    hash = "sha256-7D62asG8rirANNuR93nekb2Wqv3dUyyru5ulyI2xBDs=";
  };
  dependencies = [ litert-lm-api litert-lm-builder ] ++ (with python3Packages; [
    click
    prompt-toolkit
    typing-extensions
    questionary
  ]);
  meta = {
    description = "LiteRT-LM CLI, including the OpenAI-compatible `serve`";
    homepage = "https://github.com/google-ai-edge/LiteRT-LM";
    mainProgram = "litert-lm";
    platforms = [ "aarch64-darwin" ];
  };
}
