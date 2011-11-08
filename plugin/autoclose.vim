""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AutoClose.vim - Automatically close pair of characters: ( with ), [ with ], { with }, etc.
" Version: 2.0
" Author: Thiago Alves <talk@thiagoalves.com.br>
" Maintainer: Thiago Alves <talk@thiagoalves.com.br>
" URL: http://thiagoalves.com.br
" Licence: This script is released under the Vim License.
" Last modified: 02/02/2011
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:debug = 0

" check if script is already loaded
if s:debug == 0 && exists("g:loaded_AutoClose")
    finish "stop loading the script"
endif
let g:loaded_AutoClose = 1

let s:global_cpo = &cpo " store compatible-mode in local variable
set cpo&vim             " go into nocompatible-mode

" Determine if special handling is required for xterm/screen/vt100
" movement keys.
let s:needspecialkeyhandling = &term[:4] == "xterm"
      \ || &term[:5] == "screen" || &term[:4] == "linux"
      \ || &term[:3] == "rxvt" || &term[:4] == "urxvt"

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Functions
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetCharAhead(len)
    if col('$') == col('.')
        return "\0"
    endif
    return strpart(getline('.'), col('.')-2 + a:len, 1)
endfunction

function! s:GetCharBehind(len)
    if col('.') == 1
        return "\0"
    endif
    return strpart(getline('.'), col('.') - (1 + a:len), 1)
endfunction

function! s:GetNextChar()
    return s:GetCharAhead(1)
endfunction

function! s:GetPrevChar()
    return s:GetCharBehind(1)
endfunction

function! s:IsEmptyPair()
    let l:prev = s:GetPrevChar()
    let l:next = s:GetNextChar()
    if l:prev == "\0" || l:next == "\0"
        return 0
    endif
    return (l:prev == l:next) || (get(b:AutoClosePairs, l:prev, "\0") == l:next)
endfunction

function! s:GetCurrentSyntaxRegion()
    return synIDattr(synIDtrans(synID(line('.'), col('.'), 1)), 'name')
endfunction

function! s:GetCurrentSyntaxRegionIf(char)
    let l:origin_line = getline('.')
    let l:changed_line = strpart(l:origin_line, 0, col('.')-1) . a:char . strpart(l:origin_line, col('.')-1)
    call setline('.', l:changed_line)
    let l:region = synIDattr(synIDtrans(synID(line('.'), col('.'), 1)), 'name')
    call setline('.', l:origin_line)
    return l:region
endfunction

function! s:IsForbidden(char)
    let l:result = index(b:AutoCloseProtectedRegions, s:GetCurrentSyntaxRegion()) >= 0
    if l:result
        return l:result
    endif
    let l:region = s:GetCurrentSyntaxRegionIf(a:char)
    let l:result = index(b:AutoCloseProtectedRegions, l:region) >= 0
    return l:result || l:region == 'Comment'
endfunction

function! s:AllowQuote(char, isBS)
    let l:result = 1
    if b:AutoCloseSmartQuote
        let l:initPos = 1 + (a:isBS ? 1 : 0)
        let l:charBehind = s:GetCharBehind(l:initPos)
        let l:prev = l:charBehind
        let l:backSlashCount = 0
        while l:charBehind == '\'
            let l:backSlashCount = l:backSlashCount + 1
            let l:charBehind = s:GetCharBehind(l:initPos + l:backSlashCount)
        endwhile

        if l:backSlashCount % 2
            let l:result = 0
        else
            if a:char == "'" && l:prev =~ '[a-zA-Z0-9]'
                let l:result = 0
            endif
        endif
    endif
    return l:result
endfunction

function! s:CountQuotes(char)
    let l:currPos = col('.')-1
    let l:line = strpart(getline('.'), 0, l:currPos)
    let l:result = 0

    if l:currPos >= 0
        for q in b:AutoCloseQuotes
            if b:AutoCloseSmartQuote != 0
                let l:regex = q . '[ˆ\\' . q . ']*(\\.[ˆ\\' . q . ']*)*' . q
            else
                let l:regex = q . '[ˆ' . q . ']*' . q
            endif

            let l:closedQuoteIdx = match(l:line, l:regex)
            while l:closedQuoteIdx >= 0
                let l:matchedStr = matchstr(l:line, l:regex, l:closedQuoteIdx)
                let l:line = strpart(l:line, 0, l:closedQuoteIdx) . strpart(l:line, l:closedQuoteIdx + strlen(l:matchedStr))
                let l:closedQuoteIdx = match(l:line, l:regex)
            endwhile
        endfor

        for c in split(l:line, '\zs')
            if c == a:char
                let l:result = l:result + 1
            endif
        endfor
    endif
    return l:result
endfunction

function! s:PushBuffer(char)
    if !exists("b:AutoCloseBuffer")
        let b:AutoCloseBuffer = []
    endif
    call insert(b:AutoCloseBuffer, a:char)
endfunction

function! s:PopBuffer()
    if exists("b:AutoCloseBuffer") && len(b:AutoCloseBuffer) > 0
        call remove(b:AutoCloseBuffer, 0)
    endif
endfunction

function! s:EmptyBuffer()
    if exists("b:AutoCloseBuffer")
        let b:AutoCloseBuffer = []
    endif
endfunction

function! s:FlushBuffer()
    let l:result = ''
    if exists("b:AutoCloseBuffer")
        let l:len = len(b:AutoCloseBuffer)
        if l:len > 0
            let l:result = join(b:AutoCloseBuffer, '') . repeat("\<Left>", l:len)
            let b:AutoCloseBuffer = []
            call s:EraseCharsOnLine(l:len)
        endif
    endif
    return l:result
endfunction

function! s:InsertCharsOnLine(str)
    let l:line = getline('.')
    let l:column = col('.')-2

    if l:column < 0
        call setline('.', a:str . l:line)
    else
        call setline('.', l:line[:l:column] . a:str . l:line[l:column+1:])
    endif
endfunction

function! s:EraseCharsOnLine(len)
    let l:line = getline('.')
    let l:column = col('.')-2

    if l:column < 0
        call setline('.', l:line[a:len + 1:])
    else
        call setline('.', l:line[:l:column] . l:line[l:column + a:len + 1:])
    endif
endfunction

function! s:InsertPair(char)
    if ! b:AutoCloseOn || ! has_key(b:AutoClosePairs, a:char) || s:IsForbidden(a:char)
      return a:char
    endif

    let l:save_ve = &ve
    set ve=all

    let l:next = s:GetNextChar()
    let l:result = a:char
    " only add closing pair before space or any of the closepair chars
    let close_before = '\s\|\V\[,.;' . escape(join(keys(b:AutoClosePairs) + values(b:AutoClosePairs), ''), ']').']'
    if (l:next == "\0" || l:next =~ close_before) && s:AllowQuote(a:char, 0)
        call s:InsertCharsOnLine(b:AutoClosePairs[a:char])
        call s:PushBuffer(b:AutoClosePairs[a:char])
    endif

    exec "set ve=" . l:save_ve
    return l:result
endfunction

function! s:ClosePair(char)
    let l:save_ve = &ve
    set ve=all

    let l:result = a:char
    if b:AutoCloseOn && s:GetNextChar() == a:char
        call s:EraseCharsOnLine(1)
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return l:result
endfunction

function! s:CheckPair(char)
    let l:occur = s:CountQuotes(a:char)

    if l:occur == 0 || l:occur%2 == 0
        " Opening char
        return s:InsertPair(a:char)
    else
        " Closing char
        return s:ClosePair(a:char)
    endif
endfunction

function! s:Delete()
    let l:save_ve = &ve
    set ve=all

    if exists("b:AutoCloseBuffer") && len(b:AutoCloseBuffer) > 0 && b:AutoCloseBuffer[0] == s:GetNextChar()
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return "\<Del>"
endfunction

function! s:Backspace()
    let l:save_ve = &ve
    let l:prev = s:GetPrevChar()
    let l:next = s:GetNextChar()
    set ve=all

    if b:AutoCloseOn && s:IsEmptyPair() && (l:prev != l:next || s:AllowQuote(l:prev, 1))
        call s:EraseCharsOnLine(1)
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return "\<BS>"
endfunction

function! s:ToggleAutoClose()
    let b:AutoCloseOn = !b:AutoCloseOn
    if b:AutoCloseOn
        echo "AutoClose ON"
    else
        echo "AutoClose OFF"
    endif
endfunction

" Define variables (in the buffer namespace).
" If reset is true, the variables get reset. This is used on FileType changes.
function! s:DefineVariables(reset)
    " All the following variables can be set per buffer or global.
    " The buffer namespace is used internally, and gets reset on FileType
    " events.
    let defaults = {
                \ 'AutoClosePairs': {'(': ')', '{': '}', '[': ']', '"': '"', "'": "'",
                \                    '<': '>', '`': '`', '«': '»'},
                \ 'AutoCloseQuotes': [],
                \ 'AutoCloseProtectedRegions': ["Comment", "String", "Character"],
                \ 'AutoCloseSmartQuote': 1,
                \ 'AutoCloseOn': 1,
                \ 'AutoClosePreservDotReg': 1
                \ }

    let filetypes = split(&ft, '\.')
    if index(filetypes, 'ruby') != -1
      let defaults['AutoClosePairs']['|'] = '|'
    endif
    if index(filetypes, 'typoscript') != -1 || index(filetypes, 'zsh') != -1 || index(filetypes, 'sh') != -1
      unlet defaults['AutoClosePairs']['<']
    endif

    " Let the user define if he/she wants the plugin to do special actions when the
    " popup menu is visible and a movement key is pressed.
    " Movement keys used in the menu get mapped to themselves
    " (Up/Down/PageUp/PageDown).
    for key in s:movementKeys
        let defaults['AutoClosePumvisible'.key] = ''
    endfor
    for key in s:pumMovementKeys
        let defaults['AutoClosePumvisible'.key] = '<'.key.'>'
    endfor

    " Now handle/assign values
    for key in keys(defaults)
        if exists('l:var') | unlet l:var | endif
        if ! a:reset && exists('b:'.key)
            exec 'let l:var = b:' . key
            if type(l:var) == type(defaults[key])
                continue
            endif
        endif
        if exists('g:' . key)
            exec 'let l:var = g:' . key
            if type(l:var) == type(defaults[key])
                exec 'let b:' . key . ' = g:' . key
            endif
        else
            exec 'let b:' . key . ' = ' . string(defaults[key])
        endif
    endfor
endfunction

function! s:CreatePairsMaps()
    let l:appendQuote = (len(b:AutoCloseQuotes) == 0)
    " create appropriate maps to defined open/close characters
    for key in keys(b:AutoClosePairs)
        let map_open = ( has_key(s:mapRemap, key) ? s:mapRemap[key] : key )
        let map_close = ( has_key(s:mapRemap, b:AutoClosePairs[key]) ? s:mapRemap[b:AutoClosePairs[key]] : b:AutoClosePairs[key] )

        let open_func_arg = ( has_key(s:argRemap, map_open) ? '"' . s:argRemap[map_open] . '"' : '"' . map_open . '"' )
        let close_func_arg = ( has_key(s:argRemap, map_close) ? '"' . s:argRemap[map_close] . '"' : '"' . map_close . '"' )

        exec "vnoremap <buffer> <silent> <LEADER>a" . map_open . " <Esc>`>a" . map_close .  "<Esc>`<i" . map_open . "<Esc>"
        exec "vnoremap <buffer> <silent> <LEADER>a" . map_close . " <Esc>`>a" . map_close .  "<Esc>`<i" . map_open . "<Esc>"
        if key == b:AutoClosePairs[key]
            if l:appendQuote
                call add(b:AutoCloseQuotes, key)
            endif
            exec "inoremap <buffer> <silent> " . map_open . " <C-R>=<SID>CheckPair(" . open_func_arg . ")<CR>"
        else
            exec "inoremap <buffer> <silent> " . map_open . " <C-R>=<SID>InsertPair(" . open_func_arg . ")<CR>"
            exec "inoremap <buffer> <silent> " . map_close . " <C-R>=<SID>ClosePair(" . close_func_arg . ")<CR>"
        endif
    endfor

endfunction

function! s:CreateExtraMaps()
    " Extra mapping
    inoremap <buffer> <silent> <BS>         <C-R>=<SID>Backspace()<CR>
    inoremap <buffer> <silent> <Del>        <C-R>=<SID>Delete()<CR>

    if b:AutoClosePreservDotReg == 1
        " Fix the re-do feature by flushing the char buffer on key movements (including Escape):
        for key in s:movementKeys
            if s:needspecialkeyhandling
                exec 'imap <buffer> <silent>' . s:movementKeysXterm[key] . ' <'.key.'>'
            endif
            exe 'let l:pvisiblemap = b:AutoClosePumvisible' . key
            if len(l:pvisiblemap)
              exec "inoremap <buffer> <silent> <expr>  <" . key . ">  pumvisible() ? \"" . l:pvisiblemap . "\" : \"\\<C-R>=<SID>FlushBuffer()\\<CR>\\<" . key . ">\""
            else
              exec "inoremap <buffer> <silent> <" . key . ">  <C-R>=<SID>FlushBuffer()<CR><" . key . ">"
            endif
        endfor

        " Flush the char buffer on mouse click:
        inoremap <buffer> <silent> <LeftMouse>  <C-R>=<SID>FlushBuffer()<CR><LeftMouse>
        inoremap <buffer> <silent> <RightMouse> <C-R>=<SID>FlushBuffer()<CR><RightMouse>
    endif
endfunction

function! s:CreateMaps(reset)
    call s:DefineVariables(a:reset)
    call s:CreatePairsMaps()
    call s:CreateExtraMaps()

    let b:loaded_AutoClose = 1
endfunction

function! s:IsLoadedOnBuffer()
    return (exists("b:loaded_AutoClose") && b:loaded_AutoClose)
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" here is a dictionary of characters that need to be converted before being used as map
let s:mapRemap = {'|': '<Bar>', ' ': '<Space>'}
let s:argRemap = {'"': '\"'}

let s:movementKeys = ['Esc', 'Up', 'Down', 'Left', 'Right', 'Home', 'End', 'PageUp', 'PageDown']
let s:pumMovementKeys = ['Up', 'Down', 'PageUp', 'PageDown'] " list of keys that get mapped to themselves for pumvisible()
if s:needspecialkeyhandling
  " map s:movementKeys to xterm equivalent
  let s:movementKeysXterm = {'Esc': '<C-[>', 'Up': '<C-[>OA', 'Down': '<C-[>OB', 'Left': '<C-[>OD', 'Right': '<C-[>OC', 'Home': '<C-[>OH', 'End': '<C-[>OF', 'PageUp': '<C-[>[5~', 'PageDown': '<C-[>[6~'}
endif

augroup <Plug>(autoclose)
au!
autocmd FileType * call <SID>CreateMaps(1)
autocmd BufNewFile,BufRead,BufEnter * if !<SID>IsLoadedOnBuffer() | call <SID>CreateMaps(0) | endif
autocmd InsertEnter * call <SID>EmptyBuffer()
autocmd BufEnter * if mode() == 'i' | call <SID>EmptyBuffer() | endif
augroup END

" Define convenient commands
command! AutoCloseOn :let b:AutoCloseOn = 1
command! AutoCloseOff :let b:AutoCloseOn = 0
command! AutoCloseToggle :call s:ToggleAutoClose()
