-- macOS 简体拼音：Shift 或 CapsLock 开启时按下字母，
-- 有组合时把该大写字母纳入组合（追加到输入码），无组合时直接上屏大写字母。
local function processor(key_event, env)
  local engine = env.engine

  if key_event:release() or key_event:ctrl() or key_event:alt() or key_event:super() then
    return 2 -- kNoop
  end
  if not (key_event:shift() or key_event:caps()) then
    return 2
  end

  local ch = key_event.keycode
  local upper
  if ch >= 0x41 and ch <= 0x5A then -- 已是 A-Z
    upper = string.char(ch)
  elseif ch >= 0x61 and ch <= 0x7A then -- a-z 转大写
    upper = string.char(ch - 0x20)
  else
    return 2
  end

  if engine.context:is_composing() then
    engine.context:push_input(upper) -- 纳入组合
  else
    engine:commit_text(upper)
  end
  return 1 -- kAccepted
end

return processor
