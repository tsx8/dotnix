# pstack model configuration. One line per required role.
# budget: custom (per-role)
# GLM-5.3 is text-only. This file does not automatically reroute image input.
# Single-agent roles avoid OpenAI; OpenAI appears only in multi-agent panels (arena runners, arena cross-judge pool, architect runners).

feature, refactoring: zai-coding-cn/glm-5.3 max
bug-fix: deepseek/deepseek-flash max
perf-issue: zai-coding-cn/glm-5.3 max
hillclimb: deepseek/deepseek-flash max
judgment and prose: deepseek/deepseek-flash max
hardest tasks: zai-coding-cn/glm-5.3 max
how explorer: zai-coding-cn/glm-5.3 max
how explainer: deepseek/deepseek-flash max
why investigators: deepseek/deepseek-flash max
why synthesizer: zai-coding-cn/glm-5.3 max
reflect tooling: zai-coding-cn/glm-5.3 max
reflect judgment, divergent, synthesizer: zai-coding-cn/glm-5.3 max
arena runners: zai-coding-cn/glm-5.3 max, deepseek/deepseek-flash max, openai/gpt-6.1-sol max
arena cross-judge pool: zai-coding-cn/glm-5.3 max, deepseek/deepseek-flash max, openai/gpt-6-astra max
swarm workers: zai-coding-cn/glm-5.3 max
architect runners: zai-coding-cn/glm-5.3 max, openai/gpt-6.1-sol max
interrogate reviewers: zai-coding-cn/glm-5.3 max, deepseek/deepseek-flash max
