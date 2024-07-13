package main


import "base:runtime"
import ts "core:testing"

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
import "core:encoding/json"
import tab "core:text/table"
import str "core:strings"

import "../lang"


@(test)
testmain :: proc(_: ^ts.T) {
    log.info("Begin Tests")

    sandbox: lang.Module
    lex: lang.Lexer
    par: lang.Parser
    doc: lang.Document

    
}

