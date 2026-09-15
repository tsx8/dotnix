# CapsLock stays an ordinary key on hold; F20 is the private tap identity.
timeouts(multipurpose=0.3, suspend=0)
multipurpose_modmap("CapsLock input switch", {
    Key.CAPSLOCK: [Key.F20, Key.CAPSLOCK],
}, when=lambda ctx: cnfg.screen_has_focus and not ctx_app_is_remote)
