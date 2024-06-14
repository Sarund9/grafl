package main


import "base:runtime"
import "core:testing"

import "core:log"
import "core:fmt"
import "core:io"
import "core:os"
import "core:bytes"
import "core:strconv"
import "core:time"
import "core:slice"
import "core:reflect"
import "core:unicode/utf8"
import tab "core:text/table"
import str "core:strings"

import "../lang"


@(test)
lexer :: proc(_: ^testing.T) {
    using lang
    
    // TODO: Real tokenizer tests

    source := `import "core:std"

    derive std.shader(
        params, vertex, pixel,
    )
    
    params:
        pos: f32(2)
    
    vertex(.) = .
    pixel(.) = .3 .4 .8
    
    `
    
    lex: Lexer
    read: str.Reader

    lex.tokens = make([dynamic]lang.Tok)
    defer delete(lex.tokens)

    tokeinze(&lex, str.to_reader(&read, source))

    table := tab.init(&tab.Table{})
    defer tab.destroy(table)
    tab.padding(table, 1, 1)
    tab.header(table, "index", "type", "contents", "range")
    tab.set_cell_alignment(table, 0, 1, tab.Cell_Alignment.Center)
    tab.set_cell_alignment(table, 0, 2, tab.Cell_Alignment.Center)
    tab.set_cell_alignment(table, 0, 3, tab.Cell_Alignment.Center)
    tab.row(table, "-----", "--------------", "-----------", "--------")

    for tok, index in lex.tokens {
        // if tok.type == .Error_Unknown do continue
        
        s := tok.start.char
        e := tok.end.char

        value: string
        #partial switch tok.type {
        case .LineStart:
            value = fmt.tprint(e - s)
        case:
            value = tok.value
        }

        tab.row(table, index, tok.type, value, fmt.tprintf("{}..{}", s, e))
        tab.set_cell_alignment(table, table.nr_rows - 1, 0, tab.Cell_Alignment.Center)
        tab.set_cell_alignment(table, table.nr_rows - 1, 3, tab.Cell_Alignment.Center)
    }

    wr := io.to_write_flusher(os.stream_from_handle(os.stdout))

    for row in 0..<table.nr_rows {
        for col in 0..<table.nr_cols {
            io.write_byte(wr, '|')
            tab.write_table_cell(wr, table, row, col)
        }
        io.write_string(wr, "|\n")
    }
    io.flush(wr)
}

@(test)
parser :: proc(_: ^testing.T) {
    using lang

    /* AST:
    Object {
        "a" = Field {
            deco: [],
            value: [
                Node { .ConstNumber, &->5 },
            ]
        },
        "b" = Field {
            deco: [],
            value: 8
        },
        "c" = Field {
            deco: [],
            value: 
        },
    }
    */
    source := `
foo(): f32
`

    lex: Lexer
    par: Parser
    doc: Document

    lex.tokens = make([dynamic]lang.Tok)
    defer delete(lex.tokens)
    par.doc = &doc
    par.tokens = &lex.tokens

    tokenize_src(&lex, source)

    fmt.print("TOKENS ::")
    for t, i in lex.tokens {
        if t.type == .LineStart do fmt.println()
        fmt.printf("{} ", t)
        // if i % 5 == 0 do fmt.println()
    }
    fmt.println()

    parse(&par)

    // log.info("Tokens:", len(lex.tokens))

    for err in doc.errors {
        log.error("Err:", err.start.line, err.message)
        fmt.printfln("\t AT: '{}'", source[err.start.char:err.end.char])
    }
    
    // build := str.builder_make(context.temp_allocator)

    // str.write_string(&build, "AST:\n")
    log.info("AST:")

    /*
    "key"
        args:
        deco:
        value:
    {

    }
    */

    out := io.to_write_flusher(os.stream_from_handle(os.stdout))
    defer io.flush(out)

    indent := 1
    for key, mem in doc.members {
        using io
        wprint :: fmt.wprint

        for i in 0..<indent do fmt.print("  ")

        wprint(out, key)
        if mem.params != nil {
            write_string(out, "(")
            for param, index in mem.params {
                write_string(out, param.name)
                if index == len(mem.params) - 1 do break
                write_string(out, ", ")
            }
            write_string(out, ")")
        }

        if mem.expr != nil {
            write_string(out, " = ")
            print_expr(out, mem.expr, &indent)
            write_string(out, " ")
        }
        
        if mem.deco != nil {
            write_string(out, ":\n")
            indent += 1
            defer indent -= 1
    
            // DECO
            for i in 0..<indent do write_string(out, "  ")
            for call in mem.deco {
                write_string(out, call.callee)
                write_string(out, "(")
                for arg, index in call.args {
                    // for i in 0..<indent^ do write_string(out, "  ")
                    print_expr(out, arg, &indent)
                    if index == len(call.args) - 1 do break
                    write_string(out, ", ")
                }
                write_string(out, ")")
            }
        }
        write_string(out, "\n")

        // TODO

        // VALUE
        // for i in 0..<indent do write_string(out, "  ")
        // write_string(out, "value = ")
        
    }

    print_expr :: proc(out: io.Writer, expr: lang.Expr, indent: ^int) {
        using lang, io
        wprint :: fmt.wprint
        switch e in expr {
        case Expr_Number:
            wprint(out, e.value)
        case Expr_String:
            write_quoted_string(out, e.value)
        case Expr_Operation:
            // wprint(out, e.operator)
            write_rune(out, op_icon(e.operator))
            write_string(out, "(")

            // indent^ += 1
            for child, index in e.chilren {
                // for i in 0..<indent^ do write_string(out, "  ")
                print_expr(out, child, indent)
                if index == len(e.chilren) - 1 do break
                write_string(out, ", ")
            }
            // indent^ -= 1
            // for i in 0..<indent^ do write_string(out, "  ")
            write_string(out, ")")
        case Expr_Call:
            write_string(out, e.callee)
            write_string(out, "(")
            for arg, index in e.args {
                // for i in 0..<indent^ do write_string(out, "  ")
                print_expr(out, arg, indent)
                if index == len(e.args) - 1 do break
                write_string(out, ", ")
            }
            write_string(out, ")")
        case Expr_Var:
            write_string(out, "$")
            wprint(out, e)
        case Object:
            write_string(out, "{ ... }")
        case:
        }

        op_icon :: proc(op: Operator) -> rune {
            switch op {
            case .Add: return '+'
            case .Sub: return '-'
            case .Mul: return '*'
            case .Div: return '/'
            }
            unreachable()
        }
    }

    // print_expr :: proc(out: io.Writer, tree: []lang.Expr, index, indent: ^int) {
    //     using lang, io
    //     wprint :: fmt.wprint
    //     if index^ >= len(tree) {
    //         write_string(out, "<Out of Range>\n")
    //         return
    //     }

    //     switch expr in tree[index^] {
    //     case Expr_Number:
    //         wprint(out, expr.value)
    //         write_string(out, "\n")
    //     case Expr_Operation:
    //         wprint(out, expr.operator)
    //         write_string(out, "\n")
    //         indent^ += 1
    //         defer indent^ -= 1
    //         if index^ + int(expr.numItems) >= len(tree) {
    //             write_string(out, "<Invalid Operation>")
    //             break
    //         }

    //         for i in 0..<expr.numItems {
    //             index^ += 1
    //             for i in 0..<indent^ do write_string(out, "  ")
    //             print_expr(out, tree, index, indent)
    //         }
    //     case Expr_Var:
    //         write_string(out, string(expr))
    //         write_string(out, "\n")
    //     case Object:
    //         write_string(out, "{ ... }\n")
    //     }
    // }

    // write_cons :: proc(
    //     build: ^str.Builder, con: ^lang.Con,
    //     indent: int,
    // ) {
    //     using str
    //     for i in 0..<indent do write_string(build, "  ")
        
    //     current := con
    //     for current != nil {
    //         defer current = current.next

    //         a := 27

    //         #partial switch value in current.data {
    //         case ^lang.Con:
    //             write_string(build, "(\n")
    //             write_cons(build, value, indent + 1)
    //             write_string(build, ")\n")
    //         case:
    //             if current.data == nil {
    //                 write_string(build, "<err>")
    //             } else {
    //                 fmt.sbprint(build, current.data)
    //             }
    //         }
    //     }

    //     write_string(build, "\n")
    // }

    // indentStack := make([dynamic]u64, context.temp_allocator)
    // indent: int
    // for node, index in doc.nodes {
    //     using str
    //     for i in 0..<indent do write_string(&build, "  ")
    //     if len(indentStack) > 0 {
    //         curr := &indentStack[len(indentStack) - 1]
    //         curr^ -= 1
    //         if curr^ == 0 {
    //             pop(&indentStack)
    //             indent -= 1
    //         }
    //     }
    //     #partial switch node.type {
    //     // TODO: Print values for value nodes
    //     case:
    //         fmt.sbprintfln(&build, "{} | {}", node.type, node.delta)
    //         if node.delta > 0 {
    //             append(&indentStack, node.delta)
    //             indent += 1
    //         }
    //     }
    // }
}

main :: proc() {
    time.sleep(time.Millisecond * 50)

    context.logger = log.create_console_logger(
        opt = { .Level },
    )
    defer log.destroy_console_logger(context.logger)
    
    form: map[typeid]fmt.User_Formatter

    fmt.set_user_formatters(&form)
    fmt.register_user_formatter(typeid_of(lang.Tok), proc(
        fi: ^fmt.Info, arg: any, verb: rune,
    ) -> bool {
        if arg.id == nil || arg.data == nil {
            io.write_string(fi.writer, "<nil>", &fi.n)
            return true
        }

        assert(arg.id == typeid_of(lang.Tok))
        tok := cast(^lang.Tok) arg.data

        @static watchdog: int
        watchdog += 1
        defer watchdog -= 1
        if watchdog > 40 {
            log.panic("RECURSION ERROR")
        }

        w := fi.writer
        for ind in 0..<fi.indent {
            io.write_string(w, "  ", &fi.n)
        }

        io.write_string(w, "Tok(", &fi.n)
        
        {
            en, ok := reflect.enum_name_from_value(tok.type)
            if !ok do en = "<INVALID>"
            io.write_string(w, en, &fi.n)
        }

        io.write_string(w, ")", &fi.n)
        

        return true
    })

    // fmt.wprint()

    // lexer({})
    parser({})
}

start_table :: proc(header_entries: ..string) -> ^tab.Table {

    values := make([]any, len(header_entries), context.temp_allocator)
    for &head, index in values {
        head = any(header_entries[index])
    }

    table := tab.init(new(tab.Table))
    tab.padding(table, 1, 1)
    tab.header(table, ..values)

    tab.set_cell_alignment(table, 0, 1, tab.Cell_Alignment.Center)
    tab.set_cell_alignment(table, 0, 2, tab.Cell_Alignment.Center)
    tab.set_cell_alignment(table, 0, 3, tab.Cell_Alignment.Center)
    
    return table
}

print_table :: proc(table: ^tab.Table) {
    wr := tab.stdio_writer()

    for row in 0..<table.nr_rows {
        for col in 0..<table.nr_cols {
            io.write_byte(wr, '|')
            tab.write_table_cell(wr, table, row, col)
        }
        io.write_string(wr, "|\n")
    }
    io.flush(wr)
}


visual_table :: proc(
    items: [dynamic]$T,
    header_entries: []string,
    getrow: proc(^T) -> ([]any),
) {
    using tab

    table := init(&Table{})
    padding(table, 1, 1)
    header(table, values=header_entries)
    set_cell_alignment(table, 0, 1, tab.Cell_Alignment.Center)
    set_cell_alignment(table, 0, 2, tab.Cell_Alignment.Center)
    set_cell_alignment(table, 0, 3, tab.Cell_Alignment.Center)
    // row(table, "-----", "--------------", "-----------", "--------")

    // TODO: Add entries with getrow
    for item in items {
        vals := getrow(item)

    }

    wr := stdio_writer()

    // Header
    for hcol in 0..<table.nr_cols {
        io.write_byte(wr, '|')
        tab.write_table_cell(wr, table, row, hcol)
    }
    for hcol in 0..<table.nr_cols {
        io.write_byte(wr, '|')
        tab.write_table_cell(wr, table, row, hcol)
    }

    for row in 1..<table.nr_rows {
        for col in 0..<table.nr_cols {
            io.write_byte(wr, '|')
            tab.write_table_cell(wr, table, row, col)
        }
        io.write_string(wr, "|\n")
    }
    io.flush(wr)
}
