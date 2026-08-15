return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                library = {
                  -- Hyprland Lua config API stubs (hl.* auto-complete + diagnostics)
                  "/usr/share/hypr/stubs",
                },
              },
            },
          },
        },
      },
    },
  },
}
