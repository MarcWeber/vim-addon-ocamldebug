" simple ocaml_debug implementation following the execution steps ..{{{1
" this should its own ruby like plugin (TODO)

if !exists('g:ocaml_debug') | let g:ocaml_debug = {} | endif | let s:c = g:ocaml_debug

command! -nargs=* AsyncOcamlDebug call ocaml_debug#Setup(<f-args>)

sign define ocaml_debug_current_line text=>> linehl=Type
" not used yet:
sign define ocaml_debug_breakpoint text=O   linehl=

if !exists('*OcamlDebugMappings')
  fun! OcamlDebugMappings()
     noremap <F5> :<c-u>call ocaml_debug#Debugger("step", {'count': v:count == 0 ? 1 : v:count})<cr>
     noremap <S-F5> :<c-u>call ocaml_debug#Debugger("backstep", {'count': v:count == 0 ? 1 : v:count})<cr>
     noremap <F6> :<c-u>call ocaml_debug#Debugger("next", {'count': v:count == 0 ? 1 : v:count})<cr>
     noremap <S-F6> :<c-u>call ocaml_debug#Debugger("previous", {'count': v:count == 0 ? 1 : v:count})<cr>
     " noremap <F7> :<c-u>call ocaml_debug#Debugger("finish")<cr>
     noremap <F8> :<c-u>call ocaml_debug#Debugger("run", {'count': v:count == 0 ? 1 : v:count})<cr>
     noremap <F9> :<c-u>call ocaml_debug#Debugger("toggle_break_point")<cr>
     " noremap \xv :XDbgVarView<cr>
     " vnoremap \xv y:XDbgVarView<cr>GpV<cr>
  endf
endif
