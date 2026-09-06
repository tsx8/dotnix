set working-directory := "../.."

edit:
  sops --config modules/machine/identity/.sops.yaml modules/machine/identity/secrets.yaml
