local kAccepted, kNoop = 1, 2

local function processor(key_event, env)
  local engine = env.engine

  if engine.context:get_option("ascii_mode") then
    return kNoop
  end
  if key_event:release() or key_event:ctrl() or key_event:alt() or key_event:super() then
    return kNoop
  end
  if not (key_event:shift() or key_event:caps()) then
    return kNoop
  end

  local ch = key_event.keycode
  local upper
  if ch >= 0x41 and ch <= 0x5A then
    upper = string.char(ch)
  elseif ch >= 0x61 and ch <= 0x7A then
    upper = string.char(ch - 0x20)
  else
    return kNoop
  end

  if engine.context:is_composing() then
    engine.context:push_input(upper)
  else
    engine:commit_text(upper)
  end
  return kAccepted
end

return processor
