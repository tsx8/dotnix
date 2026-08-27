-- post-commit rejection：上屏候选被完整删除后，下次相同编码时将其与下一候选交换（一次性）。
-- 状态为模块级单槽：librime-lua 无 notifier 组件，processor 用 commit_history 的
-- 变化检测刚发生的上屏；processor 与 filter 无法按引擎共享状态，故用全局单槽。

local kNoop = 2
local kBackSpace = 0xFF08

-- 候选词上屏的记录类型；punct/raw/thru（标点、直接上屏、未处理键）忽略
local WORD_TYPES = {
  phrase = true,
  user_phrase = true,
  completion = true,
  table = true,
  user_table = true,
  sentence = true,
  simplified = true,
}

-- 单独按下时忽略、不取消删除中的修饰键
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

  -- processor 看到的是按键前的 input：组合中按"input+字母"预测完整编码，
  -- 覆盖点击候选/数字键提交（其后无按键）的场景
  if composing and not (key_event:ctrl() or key_event:alt() or key_event:super()) then
    if is_plain_letter(kc) then
      state.composing_input = now_input .. string.char(kc)
    else
      state.composing_input = now_input
    end
  end

  -- 刚发生候选上屏：history 变化 + 末记录是候选词 + 当前非组合
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
      -- 完整删除前出现其他按键：取消
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

  -- 交换成功才消费：英文等模式输入同编码时不浪费 rejection
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
