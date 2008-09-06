""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AutoClose.vim - Automatically close pair of characters: ( with ), [ with ], { with }, etc.
" Version: 1.4
" Author: Thiago Alves <thiago.salves@gmail.com>
" Maintainer: Thiago Alves <thiago.salves@gmail.com>
" URL: http://thiagoalves.org
" Licence: This script is released under the Vim License.
" Last modified: 09/05/2008 
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
    return get(s:charsToClose, l:prev, "\0") == l:next
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
    let l:result = index(s:protectedRegions, s:GetCurrentSyntaxRegion()) >= 0
    if l:result
        return l:result
    endif
    let l:region = s:GetCurrentSyntaxRegionIf(a:char)
    let l:result = index(s:protectedRegions, l:region) >= 0
    return l:result && l:region == 'Comment'
endfunction

function! s:InsertPair(char)
    let l:save_ve = &ve
    set ve=all

    let l:next = s:GetNextChar()
    let l:result = a:char
    if s:running && !s:IsForbidden(a:char) && (l:next == "\0" || l:next !~ '\w')
        let l:result .= s:charsToClose[a:char] . "\<Left>"
    endif

    exec "set ve=" . l:save_ve
    return l:result
endfunction

function! s:ClosePair(char)
    let l:save_ve = &ve
    set ve=all

    if s:running && s:GetNextChar() == a:char
        let l:result = "\<Right>"
    else
        let l:result = a:char
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

    let l:result = "\<BS>"
    if s:running && s:IsEmptyPair()
        let l:result .= "\<Del>"
    endif    

    exec "set ve=" . l:save_ve
    return l:result
endfunction

function! s:ToggleAutoClose()
    let s:running = !s:running
    if s:running
        echo "AutoClose ON"
    else
        echo "AutoClose OFF"
    endif
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" let user define which character he/she wants to autocomplete
if exists("g:AutoClosePairs") && type(g:AutoClosePairs) == type({})
    let s:charsToClose = g:AutoClosePairs
    unlet g:AutoClosePairs
else
    let s:charsToClose = {'(': ')', '{': '}', '[': ']', '"': '"', "'": "'"}
endif

" let user define in which regions the autocomplete feature should not occur
if exists("g:AutoCloseProtectedRegions") && type(g:AutoCloseProtectedRegions) == type([])
    let s:protectedRegions = g:AutoCloseProtectedRegions
    unlet g:AutoCloseProtectedRegions
else
    let s:protectedRegions = ["Comment", "String", "Character"]
endif

" let user define if he/she wants the plugin turned on when vim start. Defaul is YES
if exists("g:AutoCloseOn") && type(g:AutoCloseOn) == type(0)
    let s:running = g:AutoCloseOn
    unlet g:AutoCloseOn
else
    let s:running = 1
endif

" create appropriate maps to defined open/close characters
for key in keys(s:charsToClose)
    if key == s:charsToClose[key]
        exec "inoremap <silent> " . key . " <C-R>=<SID>CheckPair(\"" . (key == '"' ? '\"' : key) . "\")<CR>"
    else
        exec "inoremap <silent> " . key . " <C-R>=<SID>InsertPair(\"" . key . "\")<CR>"
        exec "inoremap <silent> " . s:charsToClose[key] . " <C-R>=<SID>ClosePair(\"" . s:charsToClose[key] . "\")<CR>"
    endif
endfor
exec "inoremap <silent> <BS> <C-R>=<SID>Backspace()<CR>"

" Define convenient commands
command! AutoCloseOn :let s:running = 1
command! AutoCloseOff :let s:running = 0
command! AutoCloseToggle :call s:ToggleAutoClose()
