package cli


import "core:os"
import "core:fmt"
import str "core:strings"


Parser :: struct {
    program_name,
    description,
    version,
    epilog: string,
}

@private
state: struct {
    positional: [dynamic]string,
    flags: map[string]int,

}

begin :: proc(parser: ^Parser, args: []string = nil) {
    args := args if args != nil else os.args[1:]
    using state

    for arg in args {
        if !str.has_prefix(arg, "-") {
            append(&state.positional, arg)
            continue
        }

        if len(arg) == 1 {
            
        }

        // TODO: find `:`, find `=`
        colon := str.index_rune(arg, ':')

        if colon == -1 {
            flagname := arg[1:]
            state.flags[flagname] = (state.flags[flagname] or_else 0) + 1
            continue
        }
    
        equals := str.index_rune(arg, '=')

        if equals == -1 {

            continue
        }


    }
}

add_arg :: proc() {

}


