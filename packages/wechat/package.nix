{
  callPackage,
  fetchurl,
  linuxNix,
  meta,
  pname,
}:

# Tencent silently overwrites the rolling download URL; the last-modified sentinel and version/hash are
# maintained by scripts/sh/update-wechat.sh: the version is the three-part number from the official page,
# and the hash decides content identity.
# last-modified: Mon, 12 Oct 2026 08:45:13 GMT
callPackage linuxNix {
  inherit pname meta;
  version = "4.1.13";
  src = fetchurl {
    url = "https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
    hash = "sha256-RSYYC8qYASh5FZmvEi/0eVACpXFaUQ9qZUgOK+aHQkQ=";
  };
}
