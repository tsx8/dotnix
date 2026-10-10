set working-directory := "../.."

gate BASE:
  just repo lint {{quote(BASE)}}
  just repo test

build BASE: (gate BASE)
  nh os build --hostname maco --no-update-lock-file --no-write-lock-file .#maco

test BASE: (gate BASE)
  nh os test --hostname maco --ask --no-update-lock-file --no-write-lock-file .#maco

switch LABEL="":
  @scripts/sh/os.sh switch {{quote(LABEL)}}
