{
  callPackage,
  fetchurl,
  linuxNix,
  meta,
  pname,
}:

# 腾讯滚动覆盖下载地址；last-modified 哨兵与 version/hash 由
# scripts/sh/update-wechat.sh 维护：版本取官方页三位号，内容身份由 hash 决定。
# last-modified: Fri, 18 Sep 2026 09:56:31 GMT
callPackage linuxNix {
  inherit pname meta;
  version = "4.1.13";
  src = fetchurl {
    url = "https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
    hash = "sha256-T1StKQLs1vb9xWgLc1R/gNVCO/RwsBI3pXmi5bPK7us=";
  };
}
