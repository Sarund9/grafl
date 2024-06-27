package lang


import "core:os"
import "core:log"
import "core:fmt"
import str "core:strings"
import fpath "core:path/filepath"



Module :: struct {
    docs: [dynamic]Document,
    lex: Lexer,
    par: Parser,
    path: string,
}


load_module :: proc(mod: ^Module, path: string) {
    if !os.is_dir(path) {
        return
    }
    mod.path = path
    
    mod.docs = make([dynamic]Document)

    pattern := str.concatenate({
        mod.path, "/**.grafl",
    }, context.temp_allocator)

    files, err := fpath.glob(pattern, context.temp_allocator)
    if err != .None {
        return
    }

    mod.lex.tokens = make([dynamic]Tok)
    defer delete(mod.lex.tokens)
    mod.par.tokens = &mod.lex.tokens

    for file in files {
        append(&mod.docs, Document {
            filepath = str.clone(file),
        })
        mod.par.doc = &mod.docs[len(mod.docs) - 1]
        
        tokenize_file(&mod.lex, file)

        parse(&mod.par)

        clear(&mod.lex.tokens)
    }
}

derive_print :: proc(mod: ^Module, key: string) {
    for &doc in mod.docs {
        mem, ok := &doc.members[key]
        if ok {
            var := derive_expr(&doc, mem.expr)
            fmt.println(key, "=", var)
        }
    }
}

derive_member :: proc(doc: ^Document, mem: ^Member) {

}

derive_expr :: proc(doc: ^Document, expr: Expr) -> Variant {

    assert(doc != nil)
    // TODO: Some sort of variable getter
    //  Allow functions to get their parameters
    //  Allow access to variables in general

    switch e in expr {
    case Expr_Call:
        fun, ok := doc.members[e.callee]
        if !ok do return nil
        return derive_expr(doc, fun.expr)
    case Expr_Number:
        return e.value
    case Expr_Operation:
        return derive_operation(doc, e)
    case Expr_String:
        return e.value
    case Expr_Var:
        v, ok := doc.members[string(e)]
        if !ok do return nil
        return derive_expr(doc, v.expr)
    case Object:
        return nil
    case:
        return nil
    }

    panic("Unreachable in derive_expr")
    // unreachable()

    // ------------- \\
}

derive_operation :: proc(doc: ^Document, op: Expr_Operation) -> Variant {
    switch op.operator {
    case .Add:
        v: f64 = 0.0
        for child in op.chilren {
            var, ok := derive_expr(doc, child).(f64)
            if !ok do return nil
            v += var
        }
        return v
    case .Div:
        v: f64 = 0.0
        for child in op.chilren {
            var, ok := derive_expr(doc, child).(f64)
            if !ok do return nil
            v /= var
        }
        return v
    case .Mul:
        v: f64 = 0.0
        for child in op.chilren {
            var, ok := derive_expr(doc, child).(f64)
            if !ok do return nil
            v *= var
        }
        return v
    case .Sub:
        v: f64 = 0.0
        for child in op.chilren {
            var, ok := derive_expr(doc, child).(f64)
            if !ok do return nil
            v -= var
        }
        return v
    }
    panic("Unreachable in derive_operation")
}

Variant :: union {
    string,
    f64,
}
