return {
  {
    "RedsXDD/neopywal.nvim",
    name = "neopywal",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_background = false,
      use_cache = false,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      local ok, _ = pcall(require, "neopywal")
      if ok then
        opts.colorscheme = "neopywal"
      else
        opts.colorscheme = "tokyonight"
      end
    end,
  },
}
