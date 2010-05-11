""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AutoClose.vim - Automatically close pair of characters: ( with ), [ with ], { with }, etc.
" Version: 2.0.0
" Author: Thiago Alves <thiago.salves@gmail.com>
" Maintainer: Thiago Alves <thiago.salves@gmail.com>
" URL: http://thiagoalves.org
" Licence: This script is released under the Vim License.
" Last modified: 05/10/2010
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
function! s:GetNextChar()
    if col('$') == col('.')
        return "\0"
    endif
    return strpart(getline('.'), col('.')-1, 1)
endfunction

function! s:GetPrevChar()
    if col('.') == 1
        return "\0"
    endif
    return strpart(getline('.'), col('.')-2, 1)
endfunction

function! s:IsEmptyPair()
    let l:prev = s:GetPrevChar()
    let l:next = s:GetNextChar()
    if l:prev == "\0" || l:next == "\0"
        return 0
    endif
    return get(b:AutoClosePairs, l:prev, "\0") == l:next
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

function! s:FlushBuffer()
    let l:result = ''
    if exists("b:AutoCloseBuffer")
        let l:len = len(b:AutoCloseBuffer)
        if l:len > 0
            let l:result = join(b:AutoCloseBuffer, '') . repeat("\<Left>", l:len - 1)
            let b:AutoCloseBuffer = []

            let l:line = getline('.')
            let l:column = col('.') -2
            call setline('.', l:line[:l:column] . l:line[l:column + l:len + 1:])
        endif
    endif
	return l:result
endfunction

function! s:InsertPair(char)
    let l:save_ve = &ve
    set ve=all

    let l:next = s:GetNextChar()
    let l:result = a:char
    if b:AutoCloseOn && !s:IsForbidden(a:char) && (l:next == "\0" || l:next !~ '\w')
        let l:line = getline('.')
        let l:column = col('.')-2

        if l:column < 0
            call setline('.', b:AutoClosePairs[a:char] . l:line)
        else
            call setline('.', l:line[:l:column] . b:AutoClosePairs[a:char] . l:line[l:column+1:])
        endif
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
        let l:line = getline('.')
        let l:column = col('.')-2

        if l:column < 0
            call setline('.', l:line[:1])
        else
            call setline('.', l:line[:l:column] . l:line[l:column+2:])
        endif
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return l:result
endfunction

function! s:CheckPair(char)
    let l:lastpos = 0
    let l:occur = stridx(getline('.'), a:char, l:lastpos) == 0 ? 1 : 0

    while l:lastpos > -1
        let l:lastpos = stridx(getline('.'), a:char, l:lastpos+1)
        if l:lastpos > col('.')-2
            break
        endif
        if l:lastpos >= 0
            let l:occur += 1
        endif
    endwhile

    if l:occur == 0 || l:occur%2 == 0
        " Opening char
        return s:InsertPair(a:char)
    else
        " Closing char
        return s:ClosePair(a:char)
    endif
endfunction

function! s:Backspace()
    let l:save_ve = &ve
    set ve=all

    if b:AutoCloseOn && s:IsEmptyPair()
        let l:line = getline('.')
        let l:column = col('.')-2

        if l:column < 0
            call setline('.', l:line[:1])
        else
            call setline('.', l:line[:l:column] . l:line[l:column+2:])
        endif
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

    " let user define in which regions the autocomplete feature should not occur
    if !exists("b:AutoCloseProtectedRegions") || type(b:AutoCloseProtectedRegions) != type([])
        if exists("g:AutoCloseProtectedRegions") && type(g:AutoCloseProtectedRegions) == type([])
            let b:AutoCloseProtectedRegions = g:AutoCloseProtectedRegions
        else
            let b:AutoCloseProtectedRegions = ["Comment", "String", "Character"]
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
    " create appropriate maps to defined open/close characters
    for key in keys(b:AutoClosePairs)
        let map_open = ( has_key(s:mapRemap, key) ? s:mapRemap[key] : key )
        let map_close = ( has_key(s:mapRemap, b:AutoClosePairs[key]) ? s:mapRemap[b:AutoClosePairs[key]] : b:AutoClosePairs[key] )

        let open_func_arg = ( has_key(s:argRemap, map_open) ? '"' . s:argRemap[map_open] . '"' : '"' . map_open . '"' )
        let close_func_arg = ( has_key(s:argRemap, map_close) ? '"' . s:argRemap[map_close] . '"' : '"' . map_close . '"' )

        exec "vnoremap <buffer> <silent> <LEADER>a" . map_open . " <Esc>`>a" . map_close .  "<Esc>`<i" . map_open . "<Esc>"
        exec "vnoremap <buffer> <silent> <LEADER>a" . map_close . " <Esc>`>a" . map_close .  "<Esc>`<i" . map_open . "<Esc>"
        if key == b:AutoClosePairs[key]
            exec "inoremap <buffer> <silent> " . map_open . " <C-R>=<SID>CheckPair(" . open_func_arg . ")<CR>"
        else
            exec "inoremap <buffer> <silent> " . map_open . " <C-R>=<SID>InsertPair(" . open_func_arg . ")<CR>"
            exec "inoremap <buffer> <silent> " . map_close . " <C-R>=<SID>ClosePair(" . close_func_arg . ")<CR>"
        endif
    endfor
endfunction

function! s:CreateExtraMaps()
    " Extra mapping
    inoremap <buffer> <silent> <BS> <C-R>=<SID>Backspace()<CR>

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
let s:mapRemap = {'|': '<Bar>'}
let s:argRemap = {'"': '\"'}

autocmd FileType * call <SID>CreateMaps()
autocmd BufNewFile,BufRead,BufEnter * if !<SID>IsLoadedOnBuffer() | call <SID>CreateMaps() | endif

" Define convenient commands
command! AutoCloseOn :let b:AutoCloseOn = 1
command! AutoCloseOff :let b:AutoCloseOn = 0
command! AutoCloseToggle :call s:ToggleAutoClose()
