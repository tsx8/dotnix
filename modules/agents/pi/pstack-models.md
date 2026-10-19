# pstack model configuration. One line per required role.
# budget: custom (per-role)
# GLM-5.3 is text-only. This file does not automatically reroute image input.

feature, refactoring: zai-coding-cn/glm-5.3-flash max
bug-fix: deepseek/deepseek-flash high
perf-issue: zai-coding-cn/glm-5.3 max
hillclimb: deepseek/deepseek-flash high
judgment and prose: openai/gpt-6-luna max
hardest tasks: openai/gpt-6-astra xhigh
how explorer: zai-coding-cn/glm-5.3-flash max
how explainer: openai/gpt-6-luna max
why investigators: deepseek/deepseek-flash high
why synthesizer: zai-coding-cn/glm-5.3 max
reflect tooling: zai-coding-cn/glm-5.3-flash max
reflect judgment, divergent, synthesizer: openai/gpt-6.1-sol max
arena runners: zai-coding-cn/glm-5.3-flash max, deepseek/deepseek-flash high
arena cross-judge pool: zai-coding-cn/glm-5.3 high, openai/gpt-6-luna max, openai/gpt-6.1-sol xhigh
swarm workers: zai-coding-cn/glm-5.3-flash max
architect runners: zai-coding-cn/glm-5.3 max, openai/gpt-6-luna max
interrogate reviewers: zai-coding-cn/glm-5.3-flash max, deepseek/deepseek-flash high
