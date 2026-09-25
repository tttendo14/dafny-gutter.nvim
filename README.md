# dafny-gutter.nvim

Verification-status signs for [Dafny](https://dafny.org/) in Neovim.

It renders Dafny's per-line verification status in the sign column:

| Marker | Meaning |
| --- | --- |
| Green `●` | Verified |
| Red `●` | Verification or resolution failure |
| Yellow `~` | Scheduled or verifying |
| Muted `?` | Skipped |
| Pulsing `┃` | Connector, colored like the preceding status |

The connector fills the sign column between status changes, giving a compact view of which verification result applies to each block of code.

## Requirements

- Neovim 0.9+
- Dafny language server 4.11+ configured with `--notify-line-verification-status`

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "tendo/dafny-gutter.nvim",
  lazy = false,
  opts = {},
}
```

The plugin must load before the Dafny LSP client starts, so it installs the
custom notification handler in time.

Configure the Dafny LSP server to publish its verification statuses:

```lua
{
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      dafny = {
        mason = false,
        cmd = {
          "dafny",
          "server",
          "--verify-on", "Save",
          "--notify-line-verification-status",
        },
      },
    },
  },
}
```

## Configuration

Defaults:

```lua
require("dafny-gutter").setup({
  enabled = true,
  symbols = {
    verified = "●",
    error = "●",
    pending = "~",
    skipped = "?",
    connector = "┃",
  },
  animation = {
    enabled = true,
    interval = 90,  -- milliseconds between frames
    wavelength = 12, -- lines per wave
    amplitude = 0.8, -- contrast strength, from 0 to 1
    blink_interval = 450, -- milliseconds between red states
  },
})
```

Verified lines retain the high-contrast sine-wave pulse with a bright white accent. Failed markers and their connecting pipes blink together between light and dark red. Set `animation.enabled = false` for static colors.

The plugin links its highlight groups to your colorscheme's diagnostics. Override `DafnyGutterVerified`, `DafnyGutterError`, `DafnyGutterPending`, or `DafnyGutterSkipped` to customize them.

Commands:

- `:DafnyGutterEnable`
- `:DafnyGutterDisable`

## License

MIT. See [LICENSE](LICENSE).
