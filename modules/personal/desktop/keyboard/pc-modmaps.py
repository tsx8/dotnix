modmap("PC modifier roles", {
    Key.LEFT_CTRL: Key.LEFT_CTRL,
    Key.LEFT_ALT: Key.RIGHT_CTRL,
    Key.LEFT_META: Key.LEFT_ALT,
    Key.RIGHT_ALT: Key.RIGHT_CTRL,
    Key.RIGHT_META: Key.RIGHT_ALT,
    Key.RIGHT_CTRL: Key.RIGHT_META,
}, when=lambda ctx: cnfg.screen_has_focus)
