map! <S-Insert> <C-R>+
map !aa :tabnew +Ex /etc/nixos<cr>
if exists("g:neovide")
    let g:neovide_padding_top = 15
endif
let g:neovide_transparency = 0.2
