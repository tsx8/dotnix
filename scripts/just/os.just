set working-directory := "../.."

gate:
  just repo lint
  just repo test

build: gate
  nh os build --hostname maco --no-update-lock-file --no-write-lock-file .#maco

test: gate
  nh os test --hostname maco --ask --no-update-lock-file --no-write-lock-file .#maco

switch LABEL="":
  @scripts/sh/os.sh switch {{quote(LABEL)}}
