""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AutoClose.vim - Automatically close pair of characters: ( with ), [ with ], { with }, etc.
" Version: 2.0
" Author: Thiago Alves <thiago.salves@gmail.com>
" Maintainer: Thiago Alves <thiago.salves@gmail.com>
" URL: http://thiagoalves.org
" Licence: This script is released under the Vim License.
" Last modified: 05/11/2010
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:debug = 0

" check if script is already loaded
if s:debug == 0 && exists("g:loaded_AutoClose")
    finish "stop loading the script"
endif
let g:loaded_AutoClose = 1

let s:global_cpo = &cpo " store compatible-mode in local variable
set cpo&vim             " go into nocompatible-mode

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
    return (l:prev == l:next && index(b:AutoCloseExpandChars, has_key(s:mapRemap, l:prev) ? s:mapRemap[l:prev] : l:prev) >= 0) || (get(b:AutoClosePairs, l:prev, "\0") == l:next)
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
    return l:result && l:region == 'Comment'
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

function! s:RemoveQuotes(charList, quote)
    let l:ignoreNext = 0
    let l:quoteOpened = 0
    let l:removeStart = 0
    let l:toRemove = []

    for i in range(len(a:charList))
        if l:ignoreNext
            let l:ignoreNext = 0
            continue
        endif

        if a:charList[i] == '\' && b:AutoCloseSmartQuote
            let l:ignoreNext = 1
        elseif a:charList[i] == a:quote
            if l:quoteOpened
                let l:quoteOpened = 0
                call add(l:toRemove, [l:removeStart, i])
            else
                let l:quoteOpened = 1
                let l:removeStart = i
            endif
        endif
    endfor
    for [from, to] in l:toRemove
        call remove(a:charList, from, to)
    endfor
endfunction

function! s:CountQuotes(char)
    let l:currPos = col('.')-2
    let l:line = split(getline('.'), '\zs')[:l:currPos]
    let l:result = 0

    if l:currPos >= 0
        for q in b:AutoCloseQuotes
            call s:RemoveQuotes(l:line, q)
        endfor

        let l:ignoreNext = 0
        for c in l:line
            if l:ignoreNext
                let l:ignoreNext = 0
                continue
            endif

            if c == '\' && b:AutoCloseSmartQuote
                let l:ignoreNext = 1
            elseif c == a:char
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
    let l:save_ve = &ve
    set ve=all

    let l:next = s:GetNextChar()
    let l:result = a:char
    if b:AutoCloseOn && !s:IsForbidden(a:char) && (l:next == "\0" || l:next !~ '\w') && s:AllowQuote(a:char, 0)
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
    if b:AutoCloseOn && s:GetNextChar() == a:char && s:AllowQuote(a:char, 0)
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

function! s:ExpandChar(char)
    let l:save_ve = &ve
    set ve=all

    if b:AutoCloseOn && s:IsEmptyPair()
        call s:InsertCharsOnLine(a:char)
        call s:PushBuffer(a:char)
    endif

    exec "set ve=" . l:save_ve
    return a:char
endfunction 

function! s:ExpandEnter()
    let l:save_ve = &ve
    let l:result = "\<CR>"
    set ve=all

    if b:AutoCloseOn && s:IsEmptyPair()
        let l:result = s:FlushBuffer() . "\<CR>\<Esc>kVj=o"
    endif

    exec "set ve=" . l:save_ve
    return l:result
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

function! s:DefineVariables()
    " all the following variable can be set per buffer or global. If both are set
    " the buffer variable has priority.

    " let user define which character he/she wants to autocomplete
    if !exists("b:AutoClosePairs") || type(b:AutoClosePairs) != type({})
        if exists("g:AutoClosePairs") && type(g:AutoClosePairs) == type({})
            let b:AutoClosePairs = g:AutoClosePairs
        else
            let b:AutoClosePairs = {'(': ')', '{': '}', '[': ']', '"': '"', "'": "'"}
        endif
    endif
    "
    " let user define explicit which chars should be consider quotes
    if !exists("b:AutoCloseQuotes") || type(b:AutoCloseQuotes) != type([])
        if exists("g:AutoCloseQuotes") && type(g:AutoCloseQuotes) == type([])
            let b:AutoCloseQuotes = g:AutoCloseQuotes
        else
            let b:AutoCloseQuotes = []
        endif
    endif

    " let user define in which regions the autocomplete feature should not occur
    if !exists("b:AutoCloseProtectedRegions") || type(b:AutoCloseProtectedRegions) != type([])
        if exists("g:AutoCloseProtectedRegions") && type(g:AutoCloseProtectedRegions) == type([])
            let b:AutoCloseProtectedRegions = g:AutoCloseProtectedRegions
        else
            let b:AutoCloseProtectedRegions = ["Comment", "String", "Character"]
        endif
    endif

    " let user define which characters should be used as expanded characters inside empty pairs
    if !exists("b:AutoCloseExpandChars") || type(b:AutoCloseExpandChars) != type([])
        if exists("g:AutoCloseExpandChars") && type(g:AutoCloseExpandChars) == type([])
            let b:AutoCloseExpandChars = g:AutoCloseExpandChars
        else
            let b:AutoCloseExpandChars = ["<CR>"]
        endif
    endif

    " let user define if he/she wants the plugin to do quotes on a smart way
    if !exists("b:AutoCloseSmartQuote") || type(b:AutoCloseSmartQuote) != type(0)
        if exists("g:AutoCloseSmartQuote") && type(g:AutoCloseSmartQuote) == type(0)
            let b:AutoCloseSmartQuote = g:AutoCloseSmartQuote
        else
            let b:AutoCloseSmartQuote = 1
        endif
    endif

    " let user define if he/she wants the plugin turned on when vim start. Defaul is YES
    if !exists("b:AutoCloseOn") || type(b:AutoCloseOn) != type(0)
        if exists("g:AutoCloseOn") && type(g:AutoCloseOn) == type(0)
            let b:AutoCloseOn = g:AutoCloseOn
        else
            let b:AutoCloseOn = 1
        endif
    endif
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

    for key in b:AutoCloseExpandChars
        if key == "<CR>" || key == "\<CR>" || key == ""
            inoremap <buffer> <silent> <CR> <C-R>=<SID>ExpandEnter()<CR>
        else
            exec "inoremap <buffer> <silent> " . key . " <C-R>=<SID>ExpandChar(\"" . key . "\")<CR>"
        endif
    endfor
    "inoremap <buffer> <silent> <Space> <C-R>=<SID>ExpandChar("\<Space>")<CR>
endfunction

function! s:CreateExtraMaps()
    " Extra mapping
    inoremap <buffer> <silent> <BS> <C-R>=<SID>Backspace()<CR>
    inoremap <buffer> <silent> <Del> <C-R>=<SID>Delete()<CR>

    " Fix the re-do feature:
    inoremap <buffer> <silent> <Esc> <C-R>=<SID>FlushBuffer()<CR><Esc>

    " Flush the char buffer on mouse click:
    inoremap <buffer> <silent> <LeftMouse> <C-R>=<SID>FlushBuffer()<CR><LeftMouse>
    inoremap <buffer> <silent> <RightMouse> <C-R>=<SID>FlushBuffer()<CR><RightMouse>

    " Flush the char buffer on key movements:
    inoremap <buffer> <silent> <Left> <C-R>=<SID>FlushBuffer()<CR><Left>
    inoremap <buffer> <silent> <Right> <C-R>=<SID>FlushBuffer()<CR><Right>
    inoremap <buffer> <silent> <Up> <C-R>=<SID>FlushBuffer()<CR><Up>
    inoremap <buffer> <silent> <Down> <C-R>=<SID>FlushBuffer()<CR><Down>
endfunction

function! s:CreateMaps()
    call s:DefineVariables()
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

autocmd FileType * call <SID>CreateMaps()
autocmd BufNewFile,BufRead,BufEnter * if !<SID>IsLoadedOnBuffer() | call <SID>CreateMaps() | endif
autocmd InsertEnter * call <SID>EmptyBuffer()
autocmd BufEnter * if mode() == 'i' | call <SID>EmptyBuffer() | endif

" Define convenient commands
command! AutoCloseOn :let b:AutoCloseOn = 1
command! AutoCloseOff :let b:AutoCloseOn = 0
command! AutoCloseToggle :call s:ToggleAutoClose()
