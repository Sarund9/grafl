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
    Expr_Operation,
    Object,
}

Expr_Var :: distinct string

Expr_Number :: struct {
    value: f64,
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

    tok = tokens[tok_index]

    for !exit do #partial switch tok.type {
    case .LineStart:
        space := tok.end.col - tok.start.col
        next(par) // Eat the line-start token
        
        if exit do break // End of File token

        // Attept to add a Member
        key, mem, ok := root_scope(par)
        if ok {
            doc.members[key] = mem
        }
    case:
        unexpected(par)
    }
    
    // ------------- \\

    root_scope :: proc(using par: ^Parser) -> (key: string, mem: Member, ok: bool) {
        #partial switch par.tok.type {
        case .Identifier:
            key = tok.value
            next(par) // consume identifier
            mem, ok = member(par)
            return
        case:
            log.error("Unexpected:", tok)
            unexpected(par)
        }
        return
    }
    
    member :: proc(using par: ^Parser) -> (mem: Member, ok: bool) {

        #partial switch par.tok.type {
        case .Equals:
            next(par) // consume '='
            
            // Seek range to 


            mem.expr = root_expr(par)
            ok = true
        // TODO:
        //  :  decorator
        //  :: objects
        //  () for functions
        case:
            unexpected(par)
        }
        return
    }

    root_expr :: proc(using par: ^Parser) -> Expr {
        left := primary_expr(par)
        if left == nil do return nil

        return binop_expr(par, left, 0)
    }

    primary_expr :: proc(using par: ^Parser) -> Expr {
        #partial switch par.tok.type {
        case .NumberLiteral:
            return number_expr(par)
        case .Identifier:
            return identifier_expr(par)
        case:
            unexpected(par)
        }
        return nil
    }

    binop_expr :: proc(using par: ^Parser, left: Expr, left_prec: int) -> Expr {
        left := left
        for {
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
        contents := root_expr(par)
        if contents == nil {
            return nil
        }

        if tok.type != .Paren_Right {
            errorf(par, "Excpected ')'", )
        }
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

    // finish_expr :: proc(using par: ^Parser) -> []Expr {
    //     if len(exprbuffer) == 0 do return nil

    //     slice := slice.clone(exprbuffer[:], runtime.arena_allocator(&doc.arena))
    //     clear(&exprbuffer)
    //     return slice
    // }

    next :: proc(using par: ^Parser) {
        tok_index += 1
        if tok_index >= len(tokens) {
            exit = true
            tok = {}
            return
        }
        tok = tokens[tok_index]

    }

    unexpected :: proc(using par: ^Parser) {
        append(&doc.errors, UserError {
            start = tok.start,
            end = tok.end,
            message = str.concatenate({
                "Unhandled Token: ",
                str.clone(fmt.tprint(tok)),
            }, runtime.arena_allocator(&doc.arena)),
        })
        next(par)
    }

    errorf :: proc(using par: ^Parser, format: string, args: ..any) {
        
        msg := fmt.tprintfln(format, ..args)

        append(&doc.errors, UserError {
            message = str.clone(msg, runtime.arena_allocator(&doc.arena))
        })
        // log.error("Err:", err.start.line, err.message)
    }

    node :: proc(using par: ^Parser, data: $T) -> ^T {
        n := new(T, runtime.arena_allocator(&doc.arena))
        n^ = data
        return n
    }

    // section :: proc(
    //     using doc: ^Package,
    //     tokens: []Tok,
    // ) {
    //     if len(tokens) < 2 {
    //         log.info("Small Section")
    //         return
    //     }
    //     first := tokens[0]
    //     last := tokens[len(tokens) - 1]
    //     log.infof("S: [{}] {} .. {}", len(tokens), first, last)
    //     if first.type != .LineStart {
    //         // Add syntax error
    //         append(&errors, UserError {
    //             start = first.start,
    //             end = last.end,
    //             message = "Parser: line not started",
    //         })
    //         return
    //     }

    //     // Expect

    // }
    
    // append(&nodes, ..[]Node {
    //     { type = .None, delta = 0 },
    //     { type = .None, delta = 2 },
    //         { type = .None, delta = 1 },
    //             { type = .None, delta = 0 },
    //         { type = .None, delta = 0 },

    // })

}
