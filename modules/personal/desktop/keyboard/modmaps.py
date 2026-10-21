modmap("PC modifier roles", {
    Key.LEFT_CTRL: Key.LEFT_CTRL,
    Key.LEFT_ALT: Key.RIGHT_CTRL,
    Key.LEFT_META: Key.LEFT_ALT,
    Key.RIGHT_ALT: Key.RIGHT_CTRL,
    Key.RIGHT_META: Key.RIGHT_ALT,
    Key.RIGHT_CTRL: Key.RIGHT_META,
}, when=lambda ctx: cnfg.screen_has_focus)


# CapsLock stays an ordinary key on hold; F20 is the private tap identity.
timeouts(multipurpose=0.3, suspend=0)
multipurpose_modmap("CapsLock input switch", {
    Key.CAPSLOCK: [Key.F20, Key.CAPSLOCK],
}, when=lambda ctx: cnfg.screen_has_focus and not ctx_app_is_remote)
