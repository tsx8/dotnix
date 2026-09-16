{
  callPackage,
  fetchurl,
  linuxNix,
  meta,
  pname,
}:

# 腾讯滚动覆盖下载地址；last-modified 哨兵与 version/hash 由
# scripts/sh/update-wechat.sh 维护：版本取官方页三位号，内容身份由 hash 决定。
# last-modified: Fri, 04 Sep 2026 10:41:24 GMT
callPackage linuxNix {
  inherit pname meta;
  version = "4.1.13";
  src = fetchurl {
    url = "https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.AppImage";
    hash = "sha256-ay4g5wAGNy6N37rkDqhkVkUgyHsH0BYLYA7JP3j9XMI=";
  };
}
