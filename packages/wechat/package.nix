{
  callPackage,
  fetchurl,
  linuxNix,
  meta,
  pname,
}:

# 腾讯滚动覆盖下载地址；last-modified 哨兵与 version/hash 由
# scripts/sh/update-wechat.sh 维护：版本取官方页三位号，内容身份由 hash 决定。
# last-modified: Mon, 12 Oct 2026 08:45:13 GMT
callPackage linuxNix {
  inherit pname meta;
  version = "4.1.13";
  src = fetchurl {
    url = "https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
    hash = "sha256-RSYYC8qYASh5FZmvEi/0eVACpXFaUQ9qZUgOK+aHQkQ=";
  };
}
