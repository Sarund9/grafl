package main


import "core:log"
import "cli"


main :: proc() {
    context.logger = log.create_console_logger(
        lowest = .Info,
        opt = { .Terminal_Color, .Level },
    )

    parser := cli.Parser {
        program_name = "grafl",
        description = `Gralf runtime compiler`,
        version = `0.0.1`,
        epilog = ``,
    }

    
    programVersion := `0.0.1`
    programInfo := ``


    

}

Mode :: union {
    Mode_Derive,
}

Mode_Derive :: struct {

}
