""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AutoClose.vim - Automatically close pair of characters: ( with ), [ with ], { with }, etc.
" Version: 2.0
" Author: Thiago Alves <talk@thiagoalves.com.br>
" Maintainer: Thiago Alves <talk@thiagoalves.com.br>
" URL: http://thiagoalves.com.br
" Licence: This script is released under the Vim License.
" Last modified: 02/02/2011
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" check if script is already loaded
if !exists("g:debug_AutoClose") && exists("g:loaded_AutoClose")
    finish "stop loading the script"
endif
let g:loaded_AutoClose = 1

let s:global_cpo = &cpo " store compatible-mode in local variable
set cpo&vim             " go into nocompatible-mode

if !exists('g:AutoClosePreserveDotReg')
    let g:AutoClosePreserveDotReg = 1
endif

if g:AutoClosePreserveDotReg
    " Because dot register preservation code remaps escape we have to remap
    " some terminal specific escape sequences first
    if &term =~ 'xterm' || &term =~ 'rxvt' || &term =~ 'screen' || &term =~ 'linux'
        imap <silent> <Esc>OA <Up>
        imap <silent> <Esc>OB <Down>
        imap <silent> <Esc>OC <Right>
        imap <silent> <Esc>OD <Left>
        imap <silent> <Esc>OH <Home>
        imap <silent> <Esc>OF <End>
        imap <silent> <Esc>[5~ <PageUp>
        imap <silent> <Esc>[6~ <PageDown>
    endif
endif

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

" used to implement automatic deletion of closing character when opening
" counterpart is deleted and by space expansion
function! s:IsEmptyPair()
    let l:prev = s:GetPrevChar()
    let l:next = s:GetNextChar()
    return (l:next != "\0") && (get(b:AutoClosePairs, l:prev, "\0") == l:next)
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
        for [q,closer] in items(b:AutoClosePairs)
            " only consider twin pairs
            if q != closer | continue | endif

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

" The auto-close buffer is used in a fix of the redo functionality.
" As we insert characters after cursor, we remember them and at the moment
" that vim would normally collect the last entered string into dot register
" (:help ".) - i.e. when esc or a motion key is typed in insert mode - we
" erase the inserted symbols and pretend that we have just now typed them.
" This way vim picks them up into dot register as well and user can repeat the
" typed bit with . command.
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
            call s:EraseNCharsAtCursor(l:len)
        endif
    endif
    return l:result
endfunction

function! s:InsertStringAtCursor(str)
    let l:line = getline('.')
    let l:column = col('.')-2

    if l:column < 0
        call setline('.', a:str . l:line)
    else
        call setline('.', l:line[:l:column] . a:str . l:line[l:column+1:])
    endif
endfunction

function! s:EraseNCharsAtCursor(len)
    let l:line = getline('.')
    let l:column = col('.')-2

    if l:column < 0
        call setline('.', l:line[a:len + 1:])
    else
        call setline('.', l:line[:l:column] . l:line[l:column + a:len + 1:])
    endif
endfunction

" returns the opener, after having inserted its closer if necessary
function! s:InsertPair(opener)
    if ! b:AutoCloseOn || ! has_key(b:AutoClosePairs, a:opener) || s:IsForbidden(a:opener)
      return a:opener
    endif

    let l:save_ve = &ve
    set ve=all

    let l:next = s:GetNextChar()
    " only add closing pair before space or any of the closepair chars
    let close_before = '\s\|\V\[,.;' . escape(join(keys(b:AutoClosePairs) + values(b:AutoClosePairs), ''), ']').']'
    if (l:next == "\0" || l:next =~ close_before) && s:AllowQuote(a:opener, 0)
        call s:InsertStringAtCursor(b:AutoClosePairs[a:opener])
        call s:PushBuffer(b:AutoClosePairs[a:opener])
    endif

    exec "set ve=" . l:save_ve
    return a:opener
endfunction

" returns the closer, after having eaten identical one if necessary
function! s:ClosePair(closer)
    let l:save_ve = &ve
    set ve=all

    if b:AutoCloseOn && s:GetNextChar() == a:closer
        call s:EraseNCharsAtCursor(1)
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return a:closer
endfunction

" in case closer is identical with its opener - heuristically decide which one
" is being typed and act accordingly
function! s:OpenOrCloseTwinPair(char)
    if s:CountQuotes(a:char) % 2 == 0
        " act as opening char
        return s:InsertPair(a:char)
    else
        " act as closing char
        return s:ClosePair(a:char)
    endif
endfunction

" maintain auto-close buffer when delete key is pressed
function! s:Delete()
    let l:save_ve = &ve
    set ve=all

    if exists("b:AutoCloseBuffer") && len(b:AutoCloseBuffer) > 0 && b:AutoCloseBuffer[0] == s:GetNextChar()
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return "\<Del>"
endfunction

" when backspace is pressed:
" - erase an empty pair if backspacing from inside one
" - maintain auto-close buffer
function! s:Backspace()
    let l:save_ve = &ve
    let l:prev = s:GetPrevChar()
    let l:next = s:GetNextChar()
    set ve=all

    if b:AutoCloseOn && s:IsEmptyPair() && (l:prev != l:next || s:AllowQuote(l:prev, 1))
        call s:EraseNCharsAtCursor(1)
        call s:PopBuffer()
    endif

    exec "set ve=" . l:save_ve
    return "\<BS>"
endfunction

function! s:Space()
    if b:AutoCloseOn && s:IsEmptyPair()
        call s:PushBuffer("\<Space>")
        return "\<Space>\<Space>\<Left>"
    else
        return "\<Space>"
    endif
endfunction

function! s:Enter()
    if b:AutoCloseOn && s:IsEmptyPair() && stridx( b:AutoCloseExpandEnterOn, s:GetPrevChar() ) >= 0
        return "\<CR>\<Esc>O"
    else
        return "\<CR>"
    endif
endfunction

function! s:ToggleAutoClose()
    let b:AutoCloseOn = !b:AutoCloseOn
    if b:AutoCloseOn
        echo "AutoClose ON"
    else
        echo "AutoClose OFF"
    endif
endfunction

" Parse a whitespace separated line of pairs
" single characters are assumed to be twin pairs (closer identical to
" opener)
function! AutoClose#ParsePairs(string)
    if type(a:string) == type({})
        return a:string
    elseif type(a:string) != type("")
        echoerr "AutoClose#ParsePairs(): Argument not a dictionary or a string"
        return {}
    endif

    let l:dict = {}
    for pair in split(a:string)
        " strlen is length in bytes, we want in (wide) characters
        let l:pairLen = strlen(substitute(pair,'.','x','g'))
        if l:pairLen == 1
            " assume a twin pair
            let l:dict[pair] = pair
        elseif l:pairLen == 2
            let l:dict[pair[0]] = pair[1]
        else
            echoerr "AutoClose: Bad pair string - a pair longer then two character"
            echoerr " `- String: " . a:sring
            echoerr " `- Pair: " . pair . " Pair len: " . l:pairLen
        endif
    endfor
    return l:dict
endfunction

" this function is made visible for the sake of users
function! AutoClose#DefaultPairs()
    return AutoClose#ParsePairs(g:AutoClosePairs)
endfunction

function! s:ModifyPairsList(list, pairsToAdd, openersToRemove)
    return filter(
                \ extend(a:list, AutoClose#ParsePairs(a:pairsToAdd), "force"),
                \ "stridx(a:openersToRemove,v:key)<0")
endfunction

function! AutoClose#DefaultPairsModified(pairsToAdd,openersToRemove)
    return s:ModifyPairsList(AutoClose#DefaultPairs(), a:pairsToAdd, a:openersToRemove)
endfunction

" Define variables (in the buffer namespace).
function! s:DefineVariables()
    " All the following variables can be set per buffer or global.
    " The buffer namespace is used internally
    let defaults = {
                \ 'AutoClosePairs': AutoClose#DefaultPairs(),
                \ 'AutoCloseProtectedRegions': ["Comment", "String", "Character"],
                \ 'AutoCloseSmartQuote': 1,
                \ 'AutoCloseOn': 1,
                \ 'AutoCloseSelectionWrapPrefix': '<LEADER>a',
                \ 'AutoClosePumvisible': {},
                \ 'AutoCloseExpandSpace': 1,
                \ 'AutoCloseExpandEnterOn': "{",
                \ }

    " Let the user define if he/she wants the plugin to do special actions when the
    " popup menu is visible and a movement key is pressed.
    " Movement keys used in the menu get mapped to themselves
    " (Up/Down/PageUp/PageDown).
    for key in s:movementKeys
        let defaults['AutoClosePumvisible'][key] = ''
    endfor
    for key in s:pumMovementKeys
        let defaults['AutoClosePumvisible'][key] = '<'.key.'>'
    endfor

    if exists ('b:AutoClosePairs') && type('b:AutoClosePairs') == type("")
        let tmp = AutoClose#ParsePairs(b:AutoClosePairs)
        unlet b:AutoClosePairs
        let b:AutoClosePairs = tmp
    endif

    " Now handle/assign values
    for key in keys(defaults)
        if exists('b:'.key) && type(eval('b:'.key)) == type(defaults[key])
            continue
        elseif exists('g:'.key) && type(eval('g:'.key)) == type(defaults[key])
            exec 'let b:' . key . ' = g:' . key
        else
            exec 'let b:' . key . ' = ' . string(defaults[key])
        endif
    endfor
endfunction

function! s:CreatePairsMaps()
    " create appropriate maps to defined open/close characters
    for key in keys(b:AutoClosePairs)
        let opener = s:keyName(key)
        let closer = s:keyName(b:AutoClosePairs[key])
        let quoted_opener = s:quoteAndEscape(opener)
        let quoted_closer = s:quoteAndEscape(closer)

        exec "xnoremap <buffer> <silent> ". b:AutoCloseSelectionWrapPrefix
                    \ . opener . " <Esc>`>a" . closer .  "<Esc>`<i" . opener . "<Esc>"
        exec "xnoremap <buffer> <silent> ". b:AutoCloseSelectionWrapPrefix
                    \ . closer . " <Esc>`>a" . closer .  "<Esc>`<i" . opener . "<Esc>"
        if key == b:AutoClosePairs[key]
            exec "inoremap <buffer> <silent> " . opener
                        \ . " <C-R>=<SID>OpenOrCloseTwinPair(" . quoted_opener . ")<CR>"
        else
            exec "inoremap <buffer> <silent> " . opener
                        \ . " <C-R>=<SID>InsertPair(" . quoted_opener . ")<CR>"
            exec "inoremap <buffer> <silent> " . closer
                        \ . " <C-R>=<SID>ClosePair(" . quoted_closer . ")<CR>"
        endif
    endfor
endfunction

function! s:CreateExtraMaps()
    " Extra mapping
    inoremap <buffer> <silent> <BS>         <C-R>=<SID>Backspace()<CR>
    inoremap <buffer> <silent> <Del>        <C-R>=<SID>Delete()<CR>
    if b:AutoCloseExpandSpace
        inoremap <buffer> <silent> <Space>      <C-R>=<SID>Space()<CR>
    endif
    if len(b:AutoCloseExpandEnterOn) > 0
        inoremap <buffer> <silent> <CR>      <C-R>=<SID>Enter()<CR>
    endif

    if g:AutoClosePreserveDotReg
        " Fix the re-do feature by flushing the char buffer on key movements (including Escape):
        for key in s:movementKeys
            let l:pvisiblemap = b:AutoClosePumvisible[key]
            let key = "<".key.">"
            let l:currentmap = maparg(key,"i")
            if (l:currentmap=="")|let l:currentmap=key|endif
            if len(l:pvisiblemap)
              exec "inoremap <buffer> <silent> <expr> " . key . " pumvisible() ? '" . l:pvisiblemap . "' : '<C-R>=<SID>FlushBuffer()<CR>" . l:currentmap . "'"
            else
              exec "inoremap <buffer> <silent> " . key . "  <C-R>=<SID>FlushBuffer()<CR>" . l:currentmap
            endif
        endfor

        " Flush the char buffer on mouse click:
        inoremap <buffer> <silent> <LeftMouse>  <C-R>=<SID>FlushBuffer()<CR><LeftMouse>
        inoremap <buffer> <silent> <RightMouse> <C-R>=<SID>FlushBuffer()<CR><RightMouse>
    endif
endfunction

function! s:CreateMaps()
    silent doautocmd FileType
    call s:DefineVariables()
    call s:CreatePairsMaps()
    call s:CreateExtraMaps()

    let b:loaded_AutoClose = 1
endfunction

function! s:IsLoadedOnBuffer()
    return (exists("b:loaded_AutoClose") && b:loaded_AutoClose)
endfunction

" map some characters to their key names
function! s:keyName(char)
    let s:keyNames = {'|': '<Bar>', ' ': '<Space>'}
    return get(s:keyNames,a:char,a:char)
endfunction

" escape some characters for use in strings
function! s:quoteAndEscape(char)
    let s:escapedChars = {'"': '\"'}
    return '"' . get(s:escapedChars,a:char,a:char) . '"'
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Configuration
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:AutoClosePairs_FactoryDefaults = AutoClose#ParsePairs("() {} [] ` \" '")
if !exists("g:AutoClosePairs_add") | let g:AutoClosePairs_add = "" | endif
if !exists("g:AutoClosePairs_del") | let g:AutoClosePairs_del = "" | endif
if !exists("g:AutoClosePairs")
    let g:AutoClosePairs = s:ModifyPairsList(
                \ s:AutoClosePairs_FactoryDefaults,
                \ g:AutoClosePairs_add,
                \ g:AutoClosePairs_del )
endif

let s:movementKeys = split('Esc Up Down Left Right Home End PageUp PageDown')
" list of keys that get mapped to themselves for pumvisible()
let s:pumMovementKeys = split('Up Down PageUp PageDown')


if has("gui_macvim")
    call extend(s:movementKeys,
                \ split("D-Left D-Right D-Up D-Down M-Left M-Right M-Up M-Down"))
endif

augroup <Plug>(autoclose)
au!
autocmd BufNewFile,BufRead,BufEnter * if !<SID>IsLoadedOnBuffer() | call <SID>CreateMaps() | endif
autocmd InsertEnter * call <SID>EmptyBuffer()
autocmd BufEnter * if mode() == 'i' | call <SID>EmptyBuffer() | endif
augroup END

" Define convenient commands
command! AutoCloseOn :let b:AutoCloseOn = 1
command! AutoCloseOff :let b:AutoCloseOn = 0
command! AutoCloseToggle :call s:ToggleAutoClose()
" vim:sw=4:sts=4:
