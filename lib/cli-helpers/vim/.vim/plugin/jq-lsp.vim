" jq-lsp.vim - jq language server support, plus completion driven by real data
"
" Requires:
"   - the jq-lsp binary:  go install github.com/wader/jq-lsp@master
"   - the yegappan/lsp plugin, installed from ~/.vimrc via vim-plug
"   - jq itself, for the data-aware key completion
"
" Provides:
"   :JqEdit          open the single-quoted jq program under the cursor in a
"                    scratch .jq buffer, where the language server does
"                    attach. ':w' there writes the text back into the original
"                    line(s), ':wq' writes it back and closes the window.
"   :JqInput {file}  attach a sample JSON document to a jq buffer, so that
"                    object keys can be completed with <C-x><C-u> or by simply
"                    typing '.'. ':JqInput !{cmd}' uses the stdout of {cmd}.
"                    :JqEdit sets this automatically when it finds a .json
"                    path on the shell command line it was invoked from.
"
" The language server knows the jq language - builtins, and functions defined
" with 'def' - but it never sees the data, so it cannot suggest object keys.
" That is what :JqInput is for; the two completion sources sit on separate
" keys ('omnifunc' for the server, 'completefunc' for the data) and do not
" interfere with each other.

if exists('g:loaded_jq_lsp') || &compatible
  finish
endif
let g:loaded_jq_lsp = 1

let g:jq_lsp_path = get(g:, 'jq_lsp_path', expand('~/go/bin/jq-lsp'))

" ---------------------------------------------------------------- server ---

" yegappan/lsp is loaded after ~/.vimrc, so the server has to be registered
" from the LspSetup user autocmd rather than by calling LspAddServer directly.
function! s:LspSetup() abort
  call LspOptionsSet(#{
        \   autoHighlightDiags: v:true,
        \   showDiagOnStatusLine: v:true,
        \   autoComplete: v:true,
        \   omniComplete: v:true,
        \   completionMatcher: 'fuzzy',
        \   noNewlineInCompletion: v:true,
        \ })
  call LspAddServer([#{
        \   name: 'jqlsp',
        \   filetype: ['jq'],
        \   path: g:jq_lsp_path,
        \   args: [],
        \   syncInit: v:true,
        \ }])
endfunction

augroup JqLspServer
  autocmd!
  if executable(g:jq_lsp_path)
    autocmd User LspSetup call s:LspSetup()
  endif

  " these mappings are buffer-local, so they only exist where a server
  " attached. 'omnifunc' is set by the plugin itself and must not be
  " overridden here.
  " force the completion popup even with no prefix typed, e.g. inside 'map('
  autocmd User LspAttached inoremap <buffer> <C-@> <C-\><C-o>:call lsp#completion#LspComplete(v:true)<CR>
  autocmd User LspAttached imap     <buffer> <C-Space> <C-@>
  autocmd User LspAttached nnoremap <buffer> gd    <Cmd>LspGotoDefinition<CR>
  autocmd User LspAttached nnoremap <buffer> gr    <Cmd>LspShowReferences<CR>
  autocmd User LspAttached nnoremap <buffer> K     <Cmd>LspHover<CR>
  autocmd User LspAttached nnoremap <buffer> <F3>  <Cmd>LspDiag show<CR>
  autocmd User LspAttached nnoremap <buffer> ]d    <Cmd>LspDiag next<CR>
  autocmd User LspAttached nnoremap <buffer> [d    <Cmd>LspDiag prev<CR>
  autocmd User LspAttached nnoremap <buffer> <F4>  <Cmd>LspRename<CR>
augroup END

" ------------------------------------------------------- :JqEdit / :w back ---

function! s:JqEdit() abort
  if &buftype !=# ''
    echohl ErrorMsg | echo 'JqEdit: not a normal buffer' | echohl NONE
    return
  endif
  " the searches below normally skip the character under the cursor. When the
  " cursor sits on a quote that quote belongs to the string, so include it:
  " an odd number of quotes before it on the line means it closes the string,
  " an even number means it opens it.
  let l:back = 'bnW'
  let l:fwd = 'nW'
  if getline('.')[col('.') - 1] ==# "'"
    if count(strpart(getline('.'), 0, col('.') - 1), "'") % 2 == 1
      let l:fwd = 'cnW'
    else
      let l:back = 'bcnW'
    endif
  endif
  let l:save = getcurpos()
  let l:open = searchpos("'", l:back)
  let l:close = searchpos("'", l:fwd)
  call setpos('.', l:save)
  if l:open == [0, 0]
    echohl ErrorMsg | echo "JqEdit: no opening ' before the cursor" | echohl NONE
    return
  endif
  let [l:sl, l:sc] = l:open
  if l:close == [0, 0]
    " string is still unterminated - take the rest of the opening line
    let [l:el, l:ec] = [l:sl, col([l:sl, '$'])]
  else
    let [l:el, l:ec] = l:close
  endif

  let l:lines = getline(l:sl, l:el)
  if l:sl == l:el
    let l:lines[0] = strpart(l:lines[0], l:sc, l:ec - 1 - l:sc)
  else
    let l:lines[0] = strpart(l:lines[0], l:sc)
    let l:lines[-1] = strpart(l:lines[-1], 0, l:ec - 1)
  endif

  " a .json path mentioned on the same command line is very likely the input
  let l:input = ''
  for l:cand in map(getline(l:sl, l:el), 'matchstr(v:val, ''\S\+\.json\>'')')
    if l:cand !=# '' && filereadable(expand(l:cand))
      let l:input = expand(l:cand)
      break
    endif
  endfor

  let l:origin = bufnr('%')
  let l:tmp = tempname() . '.jq'
  call writefile(l:lines, l:tmp)
  execute 'botright split' fnameescape(l:tmp)
  let b:jq_origin = l:origin
  let b:jq_range = [l:sl, l:sc, l:el, l:ec]
  augroup JqEditBuffer
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call s:JqWriteBack()
  augroup END
  if l:input !=# ''
    call s:JqSetInput(l:input)
  endif
endfunction

function! s:JqWriteBack() abort
  let l:origin = get(b:, 'jq_origin', 0)
  let l:range = get(b:, 'jq_range', [])
  if empty(l:range) || !bufloaded(l:origin)
    echohl ErrorMsg | echo 'JqEdit: original buffer is gone' | echohl NONE
    return
  endif
  let [l:sl, l:sc, l:el, l:ec] = l:range
  let l:new = getline(1, '$')
  " keep the quote characters themselves, replace only what is between them
  let l:prefix = strpart(getbufline(l:origin, l:sl)[0], 0, l:sc)
  let l:suffix = strpart(getbufline(l:origin, l:el)[0], l:ec - 1)
  if len(l:new) == 1
    let l:out = [l:prefix . l:new[0] . l:suffix]
  else
    let l:out = [l:prefix . l:new[0]] + l:new[1 : -2] + [l:new[-1] . l:suffix]
  endif

  call deletebufline(l:origin, l:sl, l:el)
  call appendbufline(l:origin, l:sl - 1, l:out)
  " the region moved, remember where it is now so a second ':w' still works
  let b:jq_range = [l:sl, l:sc, l:sl + len(l:out) - 1,
        \ len(l:out[-1]) - len(l:suffix) + 1]
  setlocal nomodified
endfunction

" ------------------------------------------------- :JqInput / key completion ---

function! s:JqSetInput(arg) abort
  if a:arg =~# '^!'
    let l:out = system(a:arg[1:])
    if v:shell_error
      echohl ErrorMsg | echo 'JqInput: command failed: ' . a:arg[1:] | echohl NONE
      return
    endif
    let l:file = tempname() . '.json'
    call writefile(split(l:out, "\n", 1), l:file)
  else
    let l:file = expand(a:arg)
  endif
  if !filereadable(l:file)
    echohl ErrorMsg | echo 'JqInput: cannot read ' . l:file | echohl NONE
    return
  endif
  let b:jq_input = l:file
  setlocal completefunc=JqDataComplete
  echo 'JqInput: ' . l:file
endfunction

" 'completefunc' has to name a global function, hence the naming here
function! JqDataComplete(findstart, base) abort
  let l:upto = strpart(getline('.'), 0, col('.') - 1)
  let l:partial = matchstr(l:upto, '[A-Za-z0-9_]*$')
  if a:findstart
    return col('.') - 1 - strlen(l:partial)
  endif
  if !exists('b:jq_input')
    return []
  endif

  " the text before the partial key must end in the '.' that selects it
  let l:head = strpart(l:upto, 0, strlen(l:upto) - strlen(l:partial))
  let l:path = matchstr(l:head,
        \ '\%(\.\%([A-Za-z_][A-Za-z0-9_]*\|"[^"]*"\)\|\[[0-9]*\]\)*\.$')
  if l:path ==# ''
    return []
  endif
  " '.foo.bar.' selects the keys of '.foo.bar', a lone '.' selects the root
  let l:base = strpart(l:path, 0, strlen(l:path) - 1)
  if l:base ==# ''
    let l:base = '.'
  endif

  let l:query = printf('[ %s | if type == "object" then (to_entries[] '
        \ . '| {k: .key, t: (.value | type)}) elif type == "array" then '
        \ . '{k: "[]", t: "array"} else empty end ] | unique_by(.k) | .[] '
        \ . '| "\(.k)\t\(.t)"', l:base)
  " systemlist() takes a string command in Vim, so quote the parts ourselves
  let l:out = systemlist('jq -r ' . shellescape(l:query)
        \ . ' ' . shellescape(b:jq_input))
  if v:shell_error
    return []
  endif

  let l:items = []
  for l:entry in l:out
    let [l:key, l:type] = split(l:entry . "\t ", "\t")[0 : 1]
    if a:base !=# '' && stridx(tolower(l:key), tolower(a:base)) != 0
      continue
    endif
    " keys that are not plain identifiers have to be quoted in a jq path
    let l:word = l:key =~# '^[A-Za-z_][A-Za-z0-9_]*$' || l:key ==# '[]'
          \ ? l:key : '"' . l:key . '"'
    call add(l:items, {'word': l:word, 'abbr': l:key,
          \ 'menu': trim(l:type), 'icase': 1})
  endfor
  return l:items
endfunction

" typing '.' opens the key list straight away, but only once a document has
" been attached, and not while typing a number like 1.5
function! s:JqDot() abort
  if !exists('b:jq_input') || getline('.')[col('.') - 2] =~# '[0-9]'
    return '.'
  endif
  return ".\<C-x>\<C-u>"
endfunction

" ------------------------------------------------------ commands, mappings ---

command! JqEdit call s:JqEdit()
command! -nargs=1 -complete=file JqInput call s:JqSetInput(<q-args>)

augroup JqLspFiletypes
  autocmd!
  autocmd FileType sh,bash,zsh nnoremap <buffer> <leader>jq :JqEdit<CR>
  autocmd FileType jq setlocal completefunc=JqDataComplete
  autocmd FileType jq inoremap <buffer><expr> . <SID>JqDot()
augroup END
