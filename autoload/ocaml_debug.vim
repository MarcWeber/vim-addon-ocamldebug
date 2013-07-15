" exec vam#DefineAndBind('s:c','g:ocaml_debug','{}')
if !exists('g:ocaml_debug') | let g:ocaml_debug = {} | endif | let s:c = g:ocaml_debug
let s:c.ctxs = get(s:c, 'ctxs', {})
let s:c.next_ctx_nr = get(s:c, 'ctx_nr', 1)

" You can also run /bin/sh and use require 'debug' in your ocaml scripts

fun! ocaml_debug#Setup(...)
  if  $OCAMLRUNPARAM == ''
    " for traces:
    let $OCAMLRUNPARAM='b'
  endif

  let cmd_prefix = 'ocamldebug -emacs'
  if a:0 > 0
    " TODO quoting?
    let cmd = cmd_prefix.' '.join(a:000," ")
  else
    let ocaml_debug = search("require\\s\\+['\"]debug['\"]",'n') >= 0  ? "" : " -redebug "
    let cmd = input('ocaml command:', cmd_prefix." ".ocaml_debug.expand('%'))
  endif
  let ctx = ocaml_debug#OcamlBuffer({'buf_name' : 'OCAML_DEBUG_PROCESS', 'cmd': 'socat "EXEC:"'.shellescape(cmd).'",pty,stderr" -', 'move_last' : 1})
  let ctx.ctx_nr = s:c.next_ctx_nr
  let ctx.vim_managed_breakpoints = []
  let ctx.next_breakpoint_nr = 1
  let s:c.ctxs[s:c.next_ctx_nr] = ctx
  let s:c.active_ctx = s:c.next_ctx_nr
  let s:c.next_ctx_nr = 1
  call OcamlDebugMappings()
  call ocaml_debug#UpdateBreakPoints()
endf

fun! ocaml_debug#OcamlBuffer(...)
  let ctx = a:0 > 0 ? a:1 : {}

  fun ctx.terminated()
    call append('$','END')
    if has_key(self, 'curr_pos')
      unlet self.curr_pos
    endif
    call ocaml_debug#SetCurr()
  endf

  call async_porcelaine#LogToBuffer(ctx)
  let ctx.receive = function('ocaml_debug#Receive')
  return ctx
endf

fun! ocaml_debug#Receive(...) dict
  call call(function('ocaml_debug#Receive2'), a:000, self)
endf
fun! ocaml_debug#Receive2(...) dict
  let self.received_data = get(self,'received_data','').a:1
  let lines = split(self.received_data,"\n",1)

  let feed = []
  let s = ""
  let set_pos = "let self.curr_pos = {'filename':m[1], 'bytepos': m[2]} | call ocaml_debug#SetCurr(m[1], m[2], m[3])"

  " process complete lines
  for l in lines[0:-2]
    if l =~ '^Program exit.'
      call ocaml_debug#SetCurr()
      break
    endif

    let m = matchlist(l, '^M\([^:]*\):\([^:]*\):\([^:]*\).*')
    " without pty:
    " let m = matchlist(l, '^(rdb:1) \([^:]\+\):\(\d\+\):')
    if len(m) > 0 && m[1] != ''
      if filereadable(m[1])
        exec set_pos
      endif
    endif
    let s .= l."\n"
  endfor

  " keep rest of line
  let self.received_data = lines[-1]

  if len(s) > 0
    call async#DelayUntilNotDisturbing('process-pid'. self.pid, {'delay-when': ['buf-invisible:'. self.bufnr], 'fun' : self.delayed_work, 'args': [s, 1], 'self': self} )
  endif
endf

" SetCurr() (no debugging active
" SetCurr(file, bytepos)
" mark that line as line which will be executed next
fun! ocaml_debug#SetCurr(...)
  " list of all current execution points of all known ocaml processes
  let curr_poss = []

  " jump to new execution point
  if a:0 != 0
    call buf_utils#GotoBuf(a:1, {'create_cmd': 'sp'})

    " set pos, use visual to select region

    exec 'goto'.(a:2 +1)
    let p = getpos('.')

    exec 'goto '.(a:3 + 1)
    normal v
    call setpos('.', p)

    let line = line('.')
    " exec a:2
    " call ocaml_debug#UpdateVarView()


    for [k,v] in items(s:c.ctxs)
      " process has finished? no more current lines
      if has_key(v, 'curr_pos')
        let cp = v.curr_pos
        let buf_nr = bufnr(cp.filename)
        if (buf_nr == -1)
          exec 'sp '.fnameescape(cp.filename)
          let buf_nr = bufnr(cp.filename)
        endif
        call add(curr_poss, [buf_nr, line, "ocaml_debug_current_line"])
      endif
      unlet k v
    endfor

  endif
  call vim_addon_signs#Push("ocaml_debug_current_line", curr_poss )

endf

fun! ocaml_debug#Debugger(cmd, opts)
  let ctx_nr = get(a:opts, 'ctx_nr',  s:c.active_ctx)
  let c = get(a:opts, 'count', 1)
  let ctx = s:c.ctxs[ctx_nr]
  if a:cmd =~ '\%(step\|backstep\|previous\|next\|finish\|run\)'
    call ctx.write(a:cmd.(c != 1 ? ' '.c : '')."\n")
    if a:cmd == 'cont'
      unlet ctx.curr_pos
      call ocaml_debug#SetCurr()
    endif
  elseif a:cmd == 'toggle_break_point'
    call ocaml_debug#ToggleLineBreakpoint()
  else
    throw "unexpected command
  endif
endf

let s:auto_break_end = '== break points end =='
fun! ocaml_debug#BreakPointsBuffer()
  let buf_name = "OCAML_BREAK_POINTS_VIEW"
  let cmd = buf_utils#GotoBuf(buf_name, {'create_cmd':'sp'} )
  if cmd == 'e'
    " new buffer, set commands etc
    let s:c.var_break_buf_nr = bufnr('%')
    noremap <buffer> <cr> :call ocaml_debug#UpdateBreakPoints()<cr>
    if getline(0, 2) != ['']
      call append(0,['# put the breakpoints here, prefix with # to deactivate:', s:auto_break_end
            \ , 'ocaml_debug supports different types of breakpoints:'
            \ , 'only this syntax is supported:  file:linenum [col]'
            \ , 'Only one breakpoint per line is supported by this file.'
            \ , ''
            \ , 'The "break @ module linenum [col]" command will be used.'
            \ , 'You can add additional breakpoints manually'
            \ , ''
            \ , 'hit <cr> to send updated breakpoints to processes'
            \ ])
    endif
    setlocal noswapfile
    " it may make sense storing breakpoints. So allow writing the breakpoints
    " buffer
    " set buftype=nofile
  endif

  let buf_nr = bufnr(buf_name)
  if buf_nr == -1
    exec 'sp '.fnameescape(buf_name)
  endif
endf


fun! ocaml_debug#UpdateBreakPoints()
  let signs = []
  let points = []
  let dct_new = {}
  call ocaml_debug#BreakPointsBuffer()

  let r_line        = '^\([^:]\+\):\(.*\)\(\s\d\+\)$'

  for l in getline('0',line('$'))
    if l =~ s:auto_break_end | break | endif
    if l =~ '^#' | continue | endif
    silent! unlet args
    let condition = ""

    let m = matchlist(l, r_line)
    if !empty(m)
      let point = {}
      let point['file'] = m[1]
      let point['line'] = m[2]
      " col is '' or ' 3' (mind the space)
      let point['col'] = m[3]
    endif

    if exists('point')
      call add(points, point)
      unlet point
    endif
  endfor

  " calculate markers:
  " we only show markers for file.line like breakpoints
  for p in points
    if has_key(p, 'file') && has_key(p, 'line')
      call add(signs, [bufnr(p.file), p.line, 'ocaml_debug_breakpoint'])
    endif
  endfor

  call vim_addon_signs#Push("ocaml_debug_breakpoint", signs )

  for ctx in values(s:c.ctxs)
    let c_ps = ctx.vim_managed_breakpoints

    if !has_key(ctx,'status')
      " for active processes update breakpoints

      " remove dropped breakpoints
      for i in range(len(c_ps)-1,0,-1)
        if !index(points, c_ps[i].point)
          call ctx.write('delete '. c_ps[i].nr ."\n")
          call remove(c_ps, i)
        endif
      endfor

      " add new breakpoints
      for b in points
        if 0 == len(filter(copy(c_ps),'v:val.point == b'))
          call add(c_ps, {'point': b, 'nr': ctx.next_breakpoint_nr})
          let ctx.next_breakpoint_nr += 1
          call ctx.write('break @ '. fnamemodify(b.file, ':t:r') .' '. (b.line -1). b.col ."\n")
        endif
      endfor
    endif
  endfor
endf


fun! ocaml_debug#ToggleLineBreakpoint()
  " yes, this implementation somehow sucks ..
  let file = expand('%')
  let line = getpos('.')[1]
  let col = getpos('.')[2]

  let old_win_nr = winnr()
  let old_buf_nr = bufnr('%')

  if !has_key(s:c,'var_break_buf_nr')
    call ocaml_debug#BreakPointsBuffer()
    let restore = "bufnr"
  else
    let win_nr = bufwinnr(get(s:c, 'var_break_buf_nr', -1))

    if win_nr == -1
      let restore = 'bufnr'
      exec 'b '.s:c.var_break_buf_nr
    else
      let restore = 'active_window'
      exec win_nr.' wincmd w'
    endif

  endif

  " BreakPoint buffer should be active now.
  let pattern = escape(file,'\').':'.line
  let line = file.':'.line.' '.col
  normal gg
  let found = search(pattern,'', s:auto_break_end)
  if found > 0
    " remove breakpoint
    exec found.'g/./d'
  else
    " add breakpoint
    call append(0, line)
  endif
  update
  call ocaml_debug#UpdateBreakPoints()
  if restore == 'bufnr'
    exec 'b '.old_buf_nr
  else
    exec old_win_nr.' wincmd w'
  endif
endf
