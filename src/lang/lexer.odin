package lang


import "base:runtime"

import "core:os"
import "core:io"
import "core:fmt"
import "core:bufio"
import "core:unicode/utf8"
import "core:strconv"
import str "core:strings"


Lexer :: struct {
    doc: ^Document,

    stream: io.Reader,
    stringBuffer: str.Builder,
    exit: bool,
    tokens: [dynamic]Tok,

    char: rune,
    charsize: int,
    current, last, start: Pos,

    linestate: enum {
        Begin,
        During,
    },
}

tokenize_src :: proc(
    using lex: ^Lexer,
    source: string,
) {
    read: str.Reader
    tokeinze(lex, str.to_reader(&read, source))
}

tokenize_file :: proc(
    using lex: ^Lexer,
    filepath: string,
) {
    handle, err := os.open(filepath)
    if err != os.ERROR_NONE do return
    defer os.close(handle)

    tokeinze(lex, io.to_reader(os.stream_from_handle(handle)))
}

tokeinze :: proc(
    using lex: ^Lexer,
    reader: io.Reader,
) {
    stream = reader
    
    current.line = 1
    current.col = 1

    str.builder_init(&stringBuffer)
    defer str.builder_destroy(&stringBuffer)

    next(lex)


    // TODO: BUGFIX
    // Place .LineStart tokens in lines without spaces
    // Use a flag to check if we have added it, reset it on a new line
    // Trim multiple LineStart tokens that are consecutive

    // if char != ' ' {
    //     send(lex, .LineStart, true)
    // }
    newline(lex)

    // ROOT
    for !exit do switch char {
    case '\n', '\r':
        linestate = .Begin
        newline(lex)
    case ' ':
        next(lex) // Skip whitespace for now..
    case '0'..='9':
        number(lex)
    case 'a'..='z', 'A'..='Z', '_':
        identifier(lex)
    case '"':
        stringlit(lex)
    case '#':
        comments(lex)
    case:
        start = last
        send(lex, operator(char), true)
        next(lex)
    }

    // ----------- \\

    // NEWLINE
    newline :: proc(using lex: ^Lexer) {
        wcount, lcount: int
        for do switch char {
        case '\n', '\r':
            wcount = 0
            next(lex)
            lcount += 1
        case ' ':
            if lcount > 0 {
                current.col = 0
                current.line += u64(lcount / 2)
                lcount = 0
            }
            if wcount == 0 {
                start = current
            }
            wcount += 1
            next(lex)
            // TODO: Count whitespace
        case:
            if lcount > 0 {
                current.col = 0
                current.line += u64(lcount / 2)
                lcount = 0
            }
            if wcount > 0 || linestate == .Begin {
                send(lex, .LineStart)
                linestate = .During
            }
            return
        }
    }

    dotstart :: proc(using lex: ^Lexer) {

    }

    comments :: proc(using lex: ^Lexer) {
        start = last
        for do switch char {
        case '\n', '\r':
            send(lex, .Comment)
            return
        case:
            str.write_rune(&stringBuffer, char)
            next(lex)
            if exit do return
        }
    }

    // IDENTIFIERS and NUMBERS
    number :: proc(using lex: ^Lexer) {
        start = last
        for do switch char {
        case 'a'..='z', 'A'..='Z', '_', '0'..='9', '.':
            str.write_rune(&stringBuffer, char)
            next(lex)
            if exit do return
        case:
            send(lex, .NumberLiteral)
            return
        }
    }

    // IDENTIFIERS and NUMBERS
    identifier :: proc(using lex: ^Lexer) {
        start = last
        for do switch char {
        case 'a'..='z', 'A'..='Z', '_', '0'..='9':
            str.write_rune(&stringBuffer, char)
            next(lex)
            if exit do return
        case:
            send(lex, .Identifier)
            return
        }
    }

    stringlit :: proc(using lex: ^Lexer) {
        start = last
        next(lex)

        defer send(lex, .StringLiteral)

        for do switch char {
        case '"':
            next(lex)
            return
        case '\n', '\r':
            // ERROR: unterminated string
            send(lex, .ErrorStringNotTerminated, clear_buffer = false)
            return
        case '\\':
            escape_seq(lex)
        case:
            str.write_rune(&stringBuffer, char)
            next(lex)

            if exit {
                send(lex, .ErrorStringNotTerminated, clear_buffer = false)
                return
            }
        }

        escape_seq :: proc(using lex: ^Lexer) {
            next(lex) // eat '\'
            if exit {
                send(lex, .ErrorStringNotTerminated, clear_buffer = false)
                return
            }
            switch char {
            case 'a':  str.write_rune(&stringBuffer, '\a')
            case 'b':  str.write_rune(&stringBuffer, '\b')
            case 'e':  str.write_rune(&stringBuffer, '\e')
            case 'f':  str.write_rune(&stringBuffer, '\f')
            case 'n':  str.write_rune(&stringBuffer, '\n')
            case 'r':  str.write_rune(&stringBuffer, '\r')
            case 't':  str.write_rune(&stringBuffer, '\t')
            case 'v':  str.write_rune(&stringBuffer, '\v')
            case '\\': str.write_rune(&stringBuffer, '\\')
            case '\"': str.write_rune(&stringBuffer, '\"')
            case '\'': str.write_rune(&stringBuffer, '\'')
            // TODO: HEX Escape Codes
            case:
                send(lex, .ErrorInvalidEscape, clear_buffer = false)
            }
            next(lex) // Eat the escape char
            if exit {
                send(lex, .ErrorStringNotTerminated, clear_buffer = false)
                return
            }
        }
    }

    // Map single runes to Operators
    operator :: proc(c: rune) -> TokType {
        switch c {
        case '{': return .Brace_Left
        case '}': return .Brace_Right
        case '(': return .Paren_Left
        case ')': return .Paren_Right
        case '[': return .Bracket_Left
        case ']': return .Bracket_Right

        case '.':  return .Dot
        case ',':  return .Comma
        case '/':  return .ForwardSlash
        case '\\': return .BackSlash
        case ':':  return .Colon
        case ';':  return .Semicolon
        case '$':  return .DollarSign
        case '@':  return .AtSign

        case '=': return .Equals
        case '+': return .Plus
        case '-': return .Minus
        case '*': return .Asterisk
        case '%': return .Percent

        case '&': return .Ampersand
        case '|': return .VerticalBar
        case '^': return .Caret
        case '~': return .Tilde

        case '<': return .LessThan
        case '>': return .GreaterThan
        case '?': return .QuestionMark

        case:
            return .Unknown
        }
    }

    send :: proc(
        using lex: ^Lexer, type: TokType,
        use_current := false,
        clear_buffer := true,
    ) {
        tok := Tok {
            type = type,
            start = lex.start,
            end = use_current ? current : last,
        }

        if str.builder_len(stringBuffer) > 0 {
            tok.value = str.clone(
                str.to_string(stringBuffer),
                runtime.arena_allocator(&doc.arena)
            )
            if clear_buffer {
                str.builder_reset(&stringBuffer)
            }
        }

        append(&tokens, tok)
    }
    
    next :: proc(using lex: ^Lexer) {
        last = current
        err: io.Error
        char, charsize, err = io.read_rune(stream)

        if err != .None {
            lex.exit = true
            return
        }

        current.char += u64(charsize)
        current.col += 1
    }

    // getstr :: proc(using lex: ^Lexer) -> string {
    //     s := string(strbuffer.buf[strbuffer_last:])
    //     strbuffer_last = len(strbuffer.buf)
    //     return s
    // }
}

open_reader :: proc(path: string) -> (read: io.Read_Closer, ok: bool) #optional_ok {
    handle, err := os.open(path)
    if err != os.ERROR_NONE do return

    read = io.to_read_closer(os.stream_from_handle(handle))
    ok = true
    return
}
