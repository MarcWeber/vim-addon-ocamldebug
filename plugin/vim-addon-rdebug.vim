" simple ocaml_debug implementation following the execution steps ..{{{1
" this should its own ruby like plugin (TODO)

if !exists('g:ocaml_debug') | let g:ocaml_debug = {} | endif | let s:c = g:ocaml_debug

command! -nargs=* AsyncOcamlDebug call ocaml_debug#Setup(<f-args>)

sign define ocaml_debug_current_line text=>> linehl=Type
" not used yet:
sign define ocaml_debug_breakpoint text=O   linehl=

if !exists('*OcamlDebugMappings')
  fun! OcamlDebugMappings()
     noremap <F5> :call ocaml_debug#Debugger("step")<cr>
     noremap <F6> :call ocaml_debug#Debugger("next")<cr>
     noremap <F7> :call ocaml_debug#Debugger("finish")<cr>
     noremap <F8> :call ocaml_debug#Debugger("run")<cr>
     noremap <F9> :call ocaml_debug#Debugger("toggle_break_point")<cr>
     " noremap \xv :XDbgVarView<cr>
     " vnoremap \xv y:XDbgVarView<cr>GpV<cr>
  endf
endif
