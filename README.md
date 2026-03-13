# goto-caller
simple plugin to jump to the caller of the current function

depends on treesitter, telescope, and correctly configured LSP

and apparently treesitter up and broke everything so this now only works with
newer versions of tree-sitter >= 0.26.6

there is no `setup()` or config, add the keybind to your config however you want, e.g.

```
vim.keymap.set("n", "so", require("goto-caller").goto_caller, { desc = "Jump to caller of current function" })
```
