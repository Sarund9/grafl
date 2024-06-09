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
import "core:unicode/utf8"
import tab "core:text/table"
import str "core:strings"

import "../lang"


SRC :: `import "core:std"

derive std.shader(
    params, vertex, pixel,
)

params:
    pos: f32(2)

vertex(.) = .
pixel(.) = .3 .4 .8

`

@(test)
lexer :: proc(_: ^testing.T) {
    using lang
    
    time.sleep(time.Millisecond * 50)

    context.logger = log.create_console_logger(
        opt = { .Level },
    )
    defer log.destroy_console_logger(context.logger)
    
    sourceCode := SRC

    lex: Lexer
    read: str.Reader

    lex.tokens = make([dynamic]lang.Tok)
    defer delete(lex.tokens)

    tokeinze(&lex, str.to_reader(&read, SRC))

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
            value = sourceCode[s:e]
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

main :: proc() {
    lexer({})
}
