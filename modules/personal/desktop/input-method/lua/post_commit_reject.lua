-- post-commit rejection: after a committed candidate is fully deleted with Backspace, swap it with the
-- next candidate the next time the same code is typed (one-shot).
-- State is a module-level single slot: librime-lua has no notifier component, so the processor detects
-- a just-committed candidate via commit_history changes; processor and filter cannot share per-engine state,
-- hence the global single slot.

local kNoop = 2
local kBackSpace = 0xFF08

-- Record types of committed candidates; punct/raw/thru (punctuation, raw input, unprocessed keys) are ignored
local WORD_TYPES = {
  phrase = true,
  user_phrase = true,
  completion = true,
  table = true,
  user_table = true,
  sentence = true,
  simplified = true,
}

-- Modifier keys ignored when pressed alone; they do not cancel an in-progress deletion
local MODIFIER_KEYS = {
  [0xFFE1] = true,
  [0xFFE2] = true,
  [0xFFE3] = true,
  [0xFFE4] = true,
  [0xFFE5] = true,
  [0xFFE6] = true,
  [0xFFE7] = true,
  [0xFFE8] = true,
  [0xFFE9] = true,
  [0xFFEA] = true,
  [0xFFEB] = true,
  [0xFFEC] = true,
}

local state = {
  phase = "idle", -- idle | deleting | rejected
  code = nil,
  text = nil,
  deleted = 0,
  chars = 0,
  prev_repr = "",
  composing_input = "",
}

local function is_plain_backspace(key_event)
  return key_event.keycode == kBackSpace
    and not (key_event:ctrl() or key_event:alt() or key_event:super())
end

local function is_plain_letter(kc)
  return (kc >= 0x41 and kc <= 0x5A) or (kc >= 0x61 and kc <= 0x7A)
end

local function processor(key_event, env)
  if key_event:release() then
    return kNoop
  end

  local ctx = env.engine.context
  local kc = key_event.keycode
  local composing = ctx:is_composing()
  local now_input = ctx.input

  -- The processor sees the input from before the key press: within a composition, an "input + letter"
  -- press predicts the full code, covering commits via candidate click/number key (no key follows)
  if composing and not (key_event:ctrl() or key_event:alt() or key_event:super()) then
    if is_plain_letter(kc) then
      state.composing_input = now_input .. string.char(kc)
    else
      state.composing_input = now_input
    end
  end

  -- A candidate was just committed: history changed + last record is a word type + currently not composing
  local history = ctx.commit_history
  local now_repr = history:repr()
  local back = history:back()
  local fresh_commit = not composing
    and now_repr ~= state.prev_repr
    and back ~= nil
    and WORD_TYPES[back.type] == true
  state.prev_repr = now_repr

  if fresh_commit then
    if is_plain_backspace(key_event) then
      state.phase = "deleting"
      state.code = state.composing_input
      state.text = back.text
      state.chars = utf8.len(back.text) or #back.text
      state.deleted = 1
      if state.deleted >= state.chars then
        state.phase = "rejected"
      end
    end
    return kNoop
  end

  if state.phase == "deleting" then
    if is_plain_backspace(key_event) then
      state.deleted = state.deleted + 1
      if state.deleted >= state.chars then
        state.phase = "rejected"
      end
    elseif not MODIFIER_KEYS[kc] then
      -- Another key before the deletion completed: cancel
      state.phase = "idle"
      state.code, state.text = nil, nil
      state.deleted, state.chars = 0, 0
    end
  end

  return kNoop
end

local function reorder(translation, env)
  if state.phase ~= "rejected" or env.engine.context.input ~= state.code then
    for cand in translation:iter() do
      yield(cand)
    end
    return
  end

  local list = {}
  for cand in translation:iter() do
    list[#list + 1] = cand
  end

  local found
  for i, cand in ipairs(list) do
    if cand.text == state.text then
      found = i
      break
    end
  end

  -- Consume only when the swap succeeds: typing the same code in English and similar modes must not waste the rejection
  if found and found < #list then
    list[found], list[found + 1] = list[found + 1], list[found]
    state.phase = "idle"
    state.code, state.text = nil, nil
  end

  for _, cand in ipairs(list) do
    yield(cand)
  end
end

return {
  processor = processor,
  reorder = reorder,
}
