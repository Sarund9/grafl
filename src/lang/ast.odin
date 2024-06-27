package lang


import "base:runtime"

import "core:log"
import "core:fmt"
import "core:strconv"
import "core:slice"
import str "core:strings"


Document :: struct {
    arena: runtime.Arena,
    
    filepath: string,

    members: Object,
    errors: [dynamic]UserError,
}

UserError :: struct {
    start, end: Pos,
    message: string,
}

Object :: map[string]Member

Member :: struct {
    expr: Expr, // 
    params: [dynamic]Param, // 
    deco: [dynamic]Expr_Call, // 
}

Param :: struct {
    name: string,
    // deco: Expr, // 
}

Expr :: union {
    Expr_Var,
    Expr_Number,
    Expr_String,
    Expr_Operation,
    Expr_Call,
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

Expr_Call :: struct {
    callee: string,
    args: [dynamic]Expr,
}

Operator :: enum {
    Add, Sub, Mul, Div,
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
        eq: bool
        
        defer {
            // TODO: Check that the Member is assigned to something
            doc.members[key.value] = mem
        }

        for !exit do #partial switch tok.type {
        case .Paren_Left: // FUNCTION DEFINITION
            function_params(par, &mem)
        case .Equals:
            if eq {
                recover(par)
                errorf(par, "Cannot assign to Property twice")
                break
            }
            next(par) // eat '='
            eq = true
            mem.expr = generic_expr(par)
        case .Colon:
            if mem.deco == nil {
                decoration_expr(par, &mem)
            } else {
                errorf(par, "Cannot ")
            }
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
    
    function_params :: proc(using par: ^Parser, mem: ^Member) {
        next(par) // eat '('
        mem.params = make([dynamic]Param, pool(par))

        // TODO: 2 state machines

        param: Param
        for !exit do #partial switch tok.type {
        case .Identifier:
            if param.name != "" {
                errorf(par, "Expected end of Argument..")
            } else {
                param.name = tok.value
            }
            next(par)
        case .Comma:
            if param.name == "" {
                errorf(par, "Expected function parameter name")
            }
            append(&mem.params, param)
            param.name = ""
            next(par)
        case .Paren_Right:
            if param.name != "" {
                // Append last parameter
                append(&mem.params, param)
            }
            next(par) // eat ')'
            return
        case .LineStart:
            next(par) // eat ')'
        case:
            unexpected(par)
        }
        // If we reach this, we have not closed the ')'
        errorf(par, "Function Params not closed")
    }

    decoration_expr :: proc(using par: ^Parser, mem: ^Member) {
        next(par) // eat ':'
        if tok.type == .LineStart {
            errorf(par, "Expected decorator argument")
            return
        }
        // TODO: Object
        //  Raise some scope here, then continue normally
        if tok.type == .Colon {
            next(par)
        }
        
        mem.deco = make([dynamic]Expr_Call, pool(par))

        for !exit do #partial switch tok.type {
        case .Identifier:
            id := tok
            next(par) // eat the identifier

            // If there's a left parenthesis, do a function call
            if tok.type == .Paren_Left {
                call, ok := call_expr(par, id.value)
                if !ok {
                    errorf(par, "Decorator syntax error")
                }
                append(&mem.deco, call)
            } else {
                // Assume identifiers as function calls.
                append(&mem.deco, Expr_Call {
                    callee = id.value,
                })
            }

        case .LineStart:
            return // Exit out
        case:
            unexpected(par)
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
                chilren = make([dynamic]Expr, pool(par))
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

        // Variable Reference
        if tok.type != .Paren_Left {
            return Expr_Var(id.value)
        }

        call, ok := call_expr(par, id.value)
        if !ok {
            // TODO: Delete ?
            return nil
        }

        return call
    }

    call_expr :: proc(
        using par: ^Parser, callee: string,
    ) -> (
        call: Expr_Call, ok: bool,
    ) {
        paren_scope += 1
        next(par) // eat '('
        call.callee = callee
        if tok.type == .Paren_Right {
            paren_scope -= 1
            next(par) // eat ')'
            return call, true
        }
        call.args = make([dynamic]Expr, pool(par))
        
        for {
            arg := generic_expr(par)
            if arg == nil {
                paren_scope -= 1
                return call, false // TODO: Recover from error ?
            }
            append(&call.args, arg)


            if tok.type == .Paren_Right {
                paren_scope -= 1
                next(par) // eat ')'        
                return call, true
            }

            if tok.type != .Comma {
                errorf(par,
                    "Expected ')' or ',' in argument list, got '{}'",
                    tok.value,
                )
            }
            next(par)
        }
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
    }

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
            case .ErrorStringNotTerminated:
                errorf(par, "String not closed: {}", tok.value)
                continue // Skip errors
            case .ErrorInvalidEscape:
                errorf(par, "Invalid escape character: {}", tok.value)
                continue // Skip errors
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
            }, pool(par)),
        })
        next(par)
    }

    errorf :: proc(using par: ^Parser, format: string, args: ..any) {
        
        msg := fmt.tprintfln(format, ..args)

        append(&doc.errors, UserError {
            message = str.clone(msg, pool(par)),
            start = tok.start,
            end = tok.end,
        })
        // log.error("Err:", err.start.line, err.message)
    }

    node :: proc(using par: ^Parser, data: $T) -> ^T {
        n := new(T, pool(par))
        n^ = data
        return n
    }

    pool :: proc(using par: ^Parser) -> runtime.Allocator {
        return runtime.arena_allocator(&doc.arena)
    }
}
