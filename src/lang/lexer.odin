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
    allocator: runtime.Allocator,
    stream: io.Reader,
    exit: bool,
    tokens: [dynamic]Tok,

    char: rune,
    charsize: int,
    current, last, start: Pos,
}

tokeinze :: proc(
    using lex: ^Lexer,
    reader: io.Reader,
) {
    stream = reader
    
    if allocator.procedure == nil {
        allocator = context.allocator
    }
    context.allocator = allocator

    current.line = 1
    current.col = 1

    // TODO: Starting Line Whitespace detection on first line

    next(lex)

    // ROOT
    for !exit do switch char {
    case '\n', '\r':
        newline(lex)
    case ' ':
        next(lex) // Skip whitespace for now..
    case '0'..='9':
        number(lex)
    case 'a'..='z', 'A'..='Z', '_':
        identifier(lex)
    case '"':
        stringlit(lex)
    case:
        start = last
        send(lex, operator(char), true)
        next(lex)
    }

    // ----------- \\

    // NEWLINE
    newline :: proc(using lex: ^Lexer) {
        wcount: int
        for do switch char {
        case '\n', '\r':
            wcount = 0
            next(lex)
        case ' ':
            if wcount == 0 {
                start = current
            }
            wcount += 1
            next(lex)
            // TODO: Count whitespace
        case:
            if wcount > 0 {
                send(lex, .LineStart)
            }
            return
        }
    }

    dotstart :: proc(using lex: ^Lexer) {

    }

    

    // IDENTIFIERS and NUMBERS
    number :: proc(using lex: ^Lexer) {
        start = last
        for do switch char {
        case 'a'..='z', 'A'..='Z', '_', '0'..='9', '.':
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
        for do switch char {
        case '"':
            next(lex)
            send(lex, .StringLiteral)
            return
        case '\n', '\r':
            // ERROR: unterminated string
            send(lex, .StringLiteral)
            return
        case:
            next(lex)

            if exit {
                // ERROR: unterminated string
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
            return .Error_Unknown
        }
    }

    send :: proc(using lex: ^Lexer, type: TokType, use_current := false) {
        append(&tokens, Tok {
            type = type,
            start = lex.start,
            end = use_current ? current : last,
        })
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
