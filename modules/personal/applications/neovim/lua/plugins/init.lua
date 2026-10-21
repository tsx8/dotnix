local registry = require("config.registry")

local specs = {}
local names = vim.tbl_keys(registry.plugins)
table.sort(names)
for _, name in ipairs(names) do
  specs[#specs + 1] = { name = name, dir = registry.plugins[name] }
end

local overrides = {
  {
    "saghen/blink.cmp",
    opts = {
      fuzzy = {
        implementation = "rust",
        prebuilt_binaries = { download = false },
      },
    },
  },
  { "mason-org/mason.nvim", enabled = false },
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers.nixd = {
        mason = false,
        -- nixd evaluates its defaults before requesting LSP settings.
        cmd_env = { NIX_PATH = "nixpkgs=" .. registry.nixpkgs },
        settings = {
          nixd = {
            formatting = { command = { "nixfmt" } },
          },
        },
      }
      opts.servers.lua_ls = vim.tbl_deep_extend("force", opts.servers.lua_ls or {}, { mason = false })
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft.nix = { "nixfmt" }
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.install_dir = registry.install_dir
    end,
  },
}

for _, spec in ipairs(overrides) do
  specs[#specs + 1] = spec
end

return specs
