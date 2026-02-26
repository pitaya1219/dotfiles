{ lib, ... }:
{
  HF_HUB_ENABLE_HF_TRANSFER = 1;
  LOGSEQ_REMOTE = "pcloud-crypt:app/logseq";
  LOGSEQ_LOCAL = "\${HOME}/storage/shared/logseq";
  PROTON_PASS_KEY_PROVIDER = "fs";

  SHELLM_MODEL = lib.mkForce "pixtral-12b-Q4_K_M";
}
