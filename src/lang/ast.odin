package lang


import "base:runtime"

import "core:log"
import "core:fmt"
import "core:strconv"
import "core:slice"
import str "core:strings"


Document :: struct {
    arena: runtime.Arena,
    
    members: Object,
    errors: [dynamic]UserError,
}

UserError :: struct {
    start, end: Pos,
    message: string,
}

Object :: map[string]Member

Member :: struct {
    // deco: ^Con, // Con is the function to call
    expr: Expr, // 
    // args: ^Con, // 
}

Expr :: union {
    Expr_Var,
    Expr_Number,
    Expr_String,
    Expr_Operation,
    Object,
}

Expr_Var :: distinct string

Expr_Number :: struct {
    value: f64,
}

Expr_String :: struct {
    value: string,
}

Expr_Operation :: struct {
    operator: Operator,
    chilren: [dynamic]Expr,
}

Operator :: enum {
    Add, Sub, Mul, Div,
}

Expr_Call :: struct {
    callee: string,
    chilren: [dynamic]Expr,
}


Parser :: struct {
    tokens: ^[dynamic]Tok,
    tok_index: int,
    tok: Tok,
    exit: bool,
    doc: ^Document,
    paren_scope: int,
}

parse :: proc(
    using par: ^Parser,
) {
    assert(tokens != nil, "Parser: no tokens list!")
    assert(doc != nil, "Parser: no package!")

    // TODO: Switch to true AST
    // Compile AST to bytecode

    if len(tokens) == 0 {
        log.error("No Tokens!")
        return
    }

    tok_index = -1
    next(par)
    // tok = tokens[tok_index]


    for !exit do #partial switch tok.type {
    case .LineStart:
        next(par) // eat line start
    case .Identifier:
        statement(par)
    case:
        unexpected(par)
    }

    // ------------- \\

    statement :: proc(using par: ^Parser) {
        key := tok
        next(par) // eat the identifier
        mem: Member
        defer doc.members[key.value] = mem

        for !exit do #partial switch tok.type {
        case .Equals:
            next(par) // eat '='
            mem.expr = generic_expr(par)

        case .LineStart: // End at line starts
            next(par)
            return
        case .Identifier:
            if mem.expr != nil {
                errorf(par, "Expected end of Statement, got '{}'", tok.value)
            } else {
                errorf(par, "'{}' not expected", tok.value)
            }
            recover(par)
        case:
            unexpected(par)
            
            // Recover from errors
            recover(par)
        }
    }
    
    generic_expr :: proc(using par: ^Parser) -> Expr {
        left := primary_expr(par)
        if left == nil do return nil

        return binop_expr(par, left, 0)
    }

    primary_expr :: proc(using par: ^Parser) -> Expr {
        for {
            #partial switch par.tok.type {
            case .Paren_Left:
                return paren_expr(par)
            case .NumberLiteral:
                return number_expr(par)
            case .Identifier:
                return identifier_expr(par)
            case .StringLiteral:
                return string_expr(par)
            case .LineStart:
                if paren_scope > 0 {
                    next(par) // skip the new-line
                    continue  // try with the next statement
                }
                errorf(par, "Expected value")
                next(par)
            case:
                unexpected(par)
            }
            return nil
        }
    }

    binop_expr :: proc(using par: ^Parser, left: Expr, left_prec: int) -> Expr {
        left := left
        for {
            // If inside paren, skip lines
            if paren_scope > 0 {
                for tok.type == .LineStart {
                    next(par)
                }
            }

            prec := precedence(tok.type)
            
            if prec < left_prec {
                return left
            }

            bin := tok
            next(par) // eat binary operator

            right := primary_expr(par)
            if right == nil {
                return nil
            }

            nextprec := precedence(tok.type)
            if prec < nextprec {
                right = binop_expr(par, right, nextprec + 1)
                if right == nil do return nil
            }

            op := operator_of(bin)

            if bop, ok := left.(Expr_Operation); ok && bop.operator == op
            {
                // Repeated Operator, merge
                
            }

            ex := Expr_Operation {
                operator = op,
                chilren = make([dynamic]Expr, runtime.arena_allocator(&doc.arena))
            }
            append(&ex.chilren, left)
            append(&ex.chilren, right)

            // Merge binary operation
            left = ex
        }
    }

    operator_of :: proc(tok: Tok) -> Operator {
        #partial switch tok.type {
        case .Plus:
            return .Add
        case .Minus:
            return .Sub
        case .Asterisk:
            return .Mul
        case .ForwardSlash:
            return .Div
        case:
            log.panic("Invalid token:", tok.type, "for operation expression")
        }
    }
    
    identifier_expr :: proc(using par: ^Parser) -> Expr {
        id := tok
        next(par) // eat the identifier

        return Expr_Var(id.value)
        
        // Variable Reference
        // if tok.type != .Paren_Left {
        //     append(&exprbuffer, Expr_Var(id.value))
        //     return true
        // }

        // TODO: Function Calls!
    }

    paren_expr :: proc(using par: ^Parser) -> Expr {
        next(par) // eat (
        paren_scope += 1
        contents := generic_expr(par)
        if contents == nil {
            paren_scope -= 1
            return nil
        }

        
        if tok.type != .Paren_Right {
            // Recover
            rec: for do #partial switch tok.type {
            case .Paren_Right:
                break rec
            case .Unknown: // End of file..
                fallthrough
            case:
                if exit do break rec
                next(par) // New lines will be skipped ...
            }
            errorf(par, "Excpected ')', got '{}'", tok.value)
            
        }
        paren_scope -= 1
        next(par)
        return contents
    }

    number_expr :: proc(using par: ^Parser) -> Expr_Number {
        num := tok
        next(par) // eat the number
        
        // TODO: Determine type to parse
        val, ok := strconv.parse_f64(num.value)

        // TODO: Handle errors

        return Expr_Number { value = ok ? val : 0 }
    }

    string_expr :: proc(using par: ^Parser) -> Expr_String {
        lit := tok
        next(par) // eat the string

        return { value = lit.value }

        // read : str.Reader
        // str.reader_init(&read, lit.value)
        // build := str.builder_make(context.temp_allocator)
        // char: rune
        // for str.reader_length(&read) > 0 {
        //     char, _, _ = str.reader_read_rune(&read) // next
        //     // BASE
        //     switch char {
        //     case '\\':
        //         char, _, _ = str.reader_read_rune(&read) // next
        //         // ESCAPE CHARS
        //         switch char {
        //         case 'a': str.write_rune(&build, '\a')
        //         case 'b': str.write_rune(&build, '\b')
        //         case 'e': str.write_rune(&build, '\e')
        //         case 'f': str.write_rune(&build, '\f')
        //         case 'n': str.write_rune(&build, '\n')
        //         case 'r': str.write_rune(&build, '\r')
        //         case 't': str.write_rune(&build, '\t')
        //         case 'v': str.write_rune(&build, '\v')
        //         case '\\': str.write_rune(&build, '\\')
        //         // TODO: Octal, Hexadecimal, Unicode16, Unicode32
        //         case '"':
        //             errorf(par, ` '\{}'`, char)
        //         case:
        //             // error
        //             errorf(par, `Unknown escape sequence '\{}'`, char)
        //         }
        //         char, _, _ = str.reader_read_rune(&read) // next
        //     case:
        //         str.write_rune(&build, char)
        //     }
        // }
        // ex: Expr_String
        // ex.value = str.clone(
        //     str.to_string(build),
        //     runtime.arena_allocator(&doc.arena),
        // )
        // return ex
    }

    // finish_expr :: proc(using par: ^Parser) -> []Expr {
    //     if len(exprbuffer) == 0 do return nil

    //     slice := slice.clone(exprbuffer[:], runtime.arena_allocator(&doc.arena))
    //     clear(&exprbuffer)
    //     return slice
    // }

    expect :: proc(
        using par: ^Parser,
        type: TokType,
        loc := #caller_location,
    ) -> (current: Tok, ok: bool) {
        current = tok
        ok = tok.type == type
        if !ok {
            unexpected(par, loc)
        } else {
            next(par) // eat the token
        }
        return
    }

    next :: proc(using par: ^Parser) {
        for {
            tok_index += 1
            if tok_index >= len(tokens) {
                exit = true
                tok = {}
                return
            }
            tok = tokens[tok_index]


            #partial switch tok.type {
            case .Comment:
                continue // Skip all comments
            case .LineStart:
                // Skip line tokens while inside parenthesis...
                if paren_scope > 0 do continue
                fallthrough
            case:
                return // Exit the function
            }
        }
    }

    recover :: proc(using par: ^Parser) {
        for !exit && tok.type != .LineStart {
            next(par)
        }
    }

    unexpected :: proc(using par: ^Parser, loc := #caller_location) {
        append(&doc.errors, UserError {
            start = tok.start,
            end = tok.end,
            message = str.concatenate({
                "Unhandled Token: ",
                str.clone(fmt.tprint(tok, "from", loc.procedure)),
            }, runtime.arena_allocator(&doc.arena)),
        })
        next(par)
    }

    errorf :: proc(using par: ^Parser, format: string, args: ..any) {
        
        msg := fmt.tprintfln(format, ..args)

        append(&doc.errors, UserError {
            message = str.clone(msg, runtime.arena_allocator(&doc.arena)),
            start = tok.start,
            end = tok.end,
        })
        // log.error("Err:", err.start.line, err.message)
    }

    node :: proc(using par: ^Parser, data: $T) -> ^T {
        n := new(T, runtime.arena_allocator(&doc.arena))
        n^ = data
        return n
    }
}
