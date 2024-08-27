map! <S-Insert> <C-R>+
map !aa :tabnew +Ex /etc/nixos<cr>
if exists("g:neovide")
    let g:neovide_padding_top = 15
    let g:neovide_transparency = 0.2
endif
highlight Normal guibg=none
highlight NonText guibg=none
highlight Normal ctermbg=none
highlight NonText ctermbg=none

