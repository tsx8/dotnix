local registry = require("config.registry")

-- LazyVim persists user state (enabled extras, news) here; the config
-- directory is read-only.
vim.g.lazyvim_json = vim.fn.stdpath("state") .. "/lazyvim.json"
vim.opt.rtp:prepend(registry.plugins["lazy.nvim"])

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "lazyvim.plugins.extras.coding.blink" },
    { import = "plugins" },
  },
  defaults = { lazy = false, version = false },
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  rocks = { enabled = false },
  lockfile = vim.fn.stdpath("state") .. "/lazy-lock.json",
  performance = { rtp = { paths = { registry.plugins.LazyVim } } },
})
