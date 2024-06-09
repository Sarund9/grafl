package lang



Tok :: struct {
    type: TokType,
    start, end: Pos,
}

TokType :: enum u16 {
    Error_Unknown,
    Identifier,
    LineStart, // First token each line, points to the line's whitespace
    StringLiteral,
    NumberLiteral,

    // TODO: Comments (# <> or #{ }#)

    Brace_Left,
    Brace_Right,
    Paren_Left,
    Paren_Right,
    Bracket_Left,
    Bracket_Right,
    
    // Text Operators
    Dot,
    Comma,
    ForwardSlash,
    BackSlash,
    Colon,
    Semicolon,
    DollarSign,
    AtSign,

    // Math Operators
    Equals,
    Plus,
    Minus,
    Asterisk,
    Percent,

    // Bitwise
    Ampersand,
    VerticalBar,
    Caret,
    Tilde,

    // Logical
    LessThan,
    GreaterThan,
    QuestionMark,
    ExclamationMark,
}

Identifier :: distinct string

Pos :: struct {
    line, char: u64,
    col: u32,
}

pos_move :: proc(pos: ^Pos, size: int) {
    pos.char += u64(size)
    pos.col += u32(size)
}

pos_skip :: proc(pos: ^Pos) {
    pos.char = 0
    pos.col = 0
    pos.line += 1
}

tok_slice :: proc(text: string, tok: Tok) -> string {
    s := tok.start.char
    e := tok.end.char

    return text[s:e]
}
