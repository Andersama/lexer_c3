module lexer;
import std::array::list;
import wheathash;
import utf8_decode;
import libc;

extern fn void printf(char*, ...);

/**
 * @require $Type.kind == TypeKind.ENUM `Only enums may be used`
 **/
macro enum_names($Type) @builtin
{
    typeid x = $Type.typeid;
    return x.names;
}

define TokenId = char;

struct Token {
    union {
        TokenId tid;
        int id;
    }
}

struct TokenInfo {
    usize offset; //offset into source
    usize length; //length from offset
    int col; //offset from newline
    int line; //line number 
}

union Simple_t {
    ichar i8;
    char  u8;

    short  i16;
    ushort u16;

    int  i32;
    uint u32;

    isize i64;
    usize u64;

    float flt;
    double dbl;

    void *ptr;
}

struct TokenData {
    Simple_t first;
    Simple_t second;
}

struct TokenPair {
    Token tkn;
    TokenInfo loc;
}

struct TrivialToken {
    char *ptr;
    usize sz;
    uint  id;
}

enum TokenizeStatus : int {
    OK,
    NO_NEW_TOKEN,
    ZERO_LENGTH_TOKEN,
    INVALID_CHAR_ID,
    BAD
}

define TokenList     = List<Token>;
define TokenInfoList = List<TokenInfo>;
define TokenDataList = List<TokenData>;
define Source        = List<char>;
define IndexList     = List<usize>;

define ScanCallback  = fn void(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current);

// buffer must have come from malloc or calloc!
fn void Source.from_cstr(Source *this, char[] buffer) {
    if(this.size > 0) {
        this.free();
    }
    this.size = buffer.len;
    this.capacity = buffer.len + 1;

    this.entries = mem::realloc(this.entries, char.sizeof * this.capacity);
    for (usize i = 0; i < this.size; i++) {
        this.entries[i] = buffer[i];
    }
    this.entries[this.size] = '\0';
}

fn void Source.from_cstr_ptr(Source *this, char* buffer_ptr) {
    if(this.size > 0) {
        this.free();
    }
    this.entries = buffer_ptr;
    for (char *t = buffer_ptr; *t; t++) {
        this.size++;
    }
    this.capacity = this.size + 1;
}

// buffer may be from a literal
fn void Source.from_literal_cstr(Source *this, char *buffer) {
    if(this.size > 0) {
        this.free();
    }
    
    for (char *t = buffer; *t; t++) {
        this.size++;
    }
    this.capacity = this.size + 1;

    this.entries = mem::realloc(this.entries, char.sizeof * this.capacity);
    
    for (usize i = 0; i < this.size; i++) {
        this.entries[i] = buffer[i];
    }
    //null-terminate
    this.entries[this.size] = '\0';
}

enum Char_id : char {
    C_START,
    //C_OTHER = C_START,
    //C_EOF = C_START,
    //C_SUBEOF = C_START,
    C_ZERO,       // 0
    C_ONE,        // 1
    C_OCT,        // 2-7
    C_DIGIT,      // 8-9
    C_HEX,        // a-fA-F
    C_UNDERSCORE, //_
    C_IDNT,       //[a-zA-Z_][a-zA-Z_0-9]*
    C_CR,         //\r
    C_LN,         //\n or \r\n
    C_LINE,       //\v\f
    C_FSLASH,     // /
    C_BSLASH,     // basic strings / chars
    // can we combine these two? (no since we nest w/ /+ merging /- becomes analgous)
    C_ADD,  //+
    C_SUB,  //-
    C_DOT,  //.
    C_STAR, //*
    C_X,
    C_B,
    C_R,
    C_E,
    C_P,
    C_SQUOTE,
    C_DQUOTE,
    C_HSPACE,
    C_PUNCT,
    C_LOPEN,
    C_RCLOSE,
    // utf8 handling see:
    // https://github.com/BobSteagall/utf_utils/blob/master/src/utf_utils.h
    C_UTF8,
    C_CR1, //- 80..8F          Continuation range 1
    C_CR2, //- 90..9F          Continuation range 2
    C_CR3, //- A0..BF          Continuation range 3
            //
    C_L2A, //- C2..DF          Leading byte range A / 2-byte sequence
            //
    C_L3A, //- E0              Leading byte range A / 3-byte sequence
    C_L3B, //- E1..EC, EE..EF  Leading byte range B / 3-byte sequence
    C_L3C, //- ED              Leading byte range C / 3-byte sequence
            //
    C_L4A, //- F0              Leading byte range A / 4-byte sequence
    C_L4B, //- F1..F3          Leading byte range B / 4-byte sequence
    C_L4C, //- F4              Leading byte range C / 4-byte sequence
    C_ILL, // C0..C1, F5..FF

    C_SIZE
    // eC_OTHER
}

enum Token_type : char {
    TKN_WHITESPACE,      // \R \N \T \F ' '
    TKN_HSPACE,          // ' ' \T
    TKN_VSPACE,          // \N \F \V?
    TKN_CARRIAGE_RETURN, // \R
    //TKN_CRLN = TKN_CARRIAGE_RETURN,
    TKN_IDENTIFIER, // [A-ZA-Z_][A-ZA-Z0-9_]*
    TKN_KEYWORD,    // SPECIAL IDENTIFIER
    TKN_RSTRING,    // R"PREFIX()PREFIX"
    //TKN_LITERALS_START = TKN_RSTRING,
    TKN_STRING,    // "SOMESTR"
    TKN_CHARACTER, // 'C'
    TKN_FLOAT,     // FLOATING POINT VALUES (DOUBLE, FLOAT, LONG DOUBLE)
    TKN_INTEGER,   // INTEGER VALUES (LONG, LONG LONG, ...ETC)
    //TKN_LITERALS_END = TKN_INTEGER,
    TKN_COMMA, // ,
    //TKN_OPERATOR_START = TKN_COMMA,
    TKN_DECL_ASSIGN, // :=
    //TKN_COLON_ASSIGN = TKN_DECL_ASSIGN,
    TKN_ASSIGN,        // =
    TKN_ADD_ASSIGN,    // +=
    TKN_SUB_ASSIGN,    // -=
    TKN_MUL_ASSIGN,    // *=
    TKN_DIV_ASSIGN,    // /=
    TKN_MOD_ASSIGN,    // %=
    TKN_XOR_ASSIGN,    // ^=
    TKN_BOR_ASSIGN,    // |=
    TKN_BNOT_ASSIGN,   // ~=
    TKN_LOR_ASSIGN,    // ||= ?
    TKN_BAND_ASSIGN,   // &=
    TKN_LAND_ASSIGN,   // &&= ?
    TKN_LSHIFT_ASSIGN, // <<=
    TKN_RSHIFT_ASSIGN, // >>=
    TKN_TERNARY,       // ? :
    TKN_LOR,           // ||
    TKN_LAND,          // &&
    TKN_BOR,           // |
    TKN_XOR,           // ^
    TKN_BAND,          // &
    TKN_EQ,            // ==
    TKN_NEQ,           // !=
    TKN_GT,            // >
    TKN_GTE,           // >=
    TKN_LT,            // <
    TKN_LTE,           // <=
    TKN_CMP,           // <=>
    TKN_RSHIFT,        // >>
    TKN_LSHIFT,        // <<
    TKN_ADD,           // +
    TKN_SUB,           // -
    TKN_MUL,           // *
    TKN_DIV,           // /
    TKN_MOD,           // %
    //TKN_REM = TKN_MOD,
    TKN_MEMBERPTR,   // .* ->* ?
    TKN_BNOT,        // ~
    TKN_LNOT,        // !
    TKN_ADDROF,      // &
    TKN_DEREF,       // *
    TKN_PREFIX_INC,  // ++
    TKN_PREFIX_DEC,  // --
    TKN_UNARY_ADD,   // +
    TKN_UNARY_SUB,   // -
    TKN_SIZEOF,      // SIZEOF
    TKN_PSTFIX_INC,  // ++
    TKN_PSTFIX_DEC,  // --
    TKN_FUNC_CALL,   // A(EXPR,...)
    TKN_ARRAY_INDEX, // B(EXPR,...)
    TKN_DOT,         // .
    //TKN_MEMBERDOT = TKN_DOT,
    TKN_SCOPE, // ::
    /*
    TKN_LPAREN,        // (
    TKN_RPAREN,        // )
    TKN_LCURLY,        // {
    TKN_RCURLY,        // }
    TKN_LBRACE,        // [
    TKN_RBRACE,        // ]
    */
    TKN_LPAREN, // (
    TKN_LCURLY, // {
    TKN_LBRACE, // [
    TKN_RPAREN, // )
    TKN_RCURLY, // }
    TKN_RBRACE, // ]
    //TKN_OPERATOR_END = TKN_RBRACE,
    TKN_COLON,        // :
    TKN_SEMICOLON,    // ;
    TKN_HASH,         // #
    TKN_SINGLE_QUOTE, // '
    TKN_DOUBLE_QUOTE, // "
    TKN_DOLLAR,       // $
    TKN_AT,           // @
    TKN_BACKSLASH,    //
    TKN_UNDERSCORE,   // _
    TKN_BACKTICK,     // `
    TKN_NUM,          // 0 - 9
    TKN_ZERO,
    TKN_ARROW,    // ->
    TKN_RANGE,    //..
    TKN_ELLIPSIS, //...
    TKN_DEL,
    TKN_UTF8,
    TKN__SIZE
    /*
    tkn_zero = 128,   // not used
    tkn_one,
    tkn_two,
    tkn_three,
    tkn_four,
    tkn_five,
    tkn_six,
    tkn_seven,
    tkn_eight,
    tkn_nine
    */
}
/*
fn char[256] digit_table() {
    char[256] lamda_table;

    for (usize i = 0; i < lamda_table.size(); i++)
        lamda_table[i] = 255;
    for (usize i = '0'; i <= '9'; i++)
        lamda_table[i] = i - (usize)'0';
    for (usize i = 'a'; i <= 'z'; i++)
        lamda_table[i] = i + 10 - (usize)'a';
    for (usize i = 'A'; i <= 'Z'; i++)
        lamda_table[i] = i + 10 - (usize)'A';

    return lamda_table;
}
*/
const char[256] CHAR_TO_DIGIT = {
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    255,
    255,
    255,
    255,
    255,
    255,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
    24,
    25,
    26,
    27,
    28,
    29,
    30,
    31,
    32,
    33,
    34,
    35,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255,
    255
};

const Char_id[256] CHAR_ID_TABLE = {
    Char_id.C_START,      //Char_id.C_EOF, // 0: non printable characters 0 - 31
    Char_id.C_HSPACE,     // 1: header start
    Char_id.C_HSPACE,     // 2: text start
    Char_id.C_HSPACE,     // 3: text end
    Char_id.C_HSPACE,     // 4: transmission end
    Char_id.C_HSPACE,     // 5: enquiry
    Char_id.C_HSPACE,     // 6: acknowledge
    Char_id.C_HSPACE,     // 7: bell
    Char_id.C_HSPACE,     // 8: backspace
    Char_id.C_HSPACE,     // 9: tab \t
    Char_id.C_LN,         // 10: line feed \n
    Char_id.C_LINE,       // 11: vertical tab \v
    Char_id.C_LINE,       // 12: form feed \f
    Char_id.C_CR,         // 13: carriage return \r
    Char_id.C_HSPACE,     // 14: shift out
    Char_id.C_HSPACE,     // 15: shift in
    Char_id.C_HSPACE,     // 16: 16 DLE
    Char_id.C_HSPACE,     // 17: DC1
    Char_id.C_HSPACE,     // 18: DC2
    Char_id.C_HSPACE,     // 19: DC3
    Char_id.C_HSPACE,     // 20: DC4
    Char_id.C_HSPACE,     // 21: NAK
    Char_id.C_HSPACE,     // 22: SYN
    Char_id.C_HSPACE,     // 23: ETB
    Char_id.C_HSPACE,     // 24: CAN
    Char_id.C_HSPACE,     // 25: EM
    Char_id.C_START,     // 26: SUB //Char_id.C_SUBEOF,
    Char_id.C_HSPACE,     // 27: ESC
    Char_id.C_HSPACE,     // 28: FS
    Char_id.C_HSPACE,     // 29: GS
    Char_id.C_HSPACE,     // 30: RS
    Char_id.C_HSPACE,     // 31: US
    Char_id.C_HSPACE,     // 32: ' '
    Char_id.C_PUNCT,      // 33: !
    Char_id.C_DQUOTE,     // 34: "
    Char_id.C_PUNCT,      // 35: #
    Char_id.C_PUNCT,      // 36: $
    Char_id.C_PUNCT,      // 37: %
    Char_id.C_PUNCT,      // 38: &
    Char_id.C_SQUOTE,     // 39: '
    Char_id.C_LOPEN,      // 40: (
    Char_id.C_RCLOSE,     // 41: )
    Char_id.C_STAR,       // 42: *
    Char_id.C_ADD,        // 43: +
    Char_id.C_PUNCT,      // 44: ,
    Char_id.C_SUB,        // 45: -
    Char_id.C_DOT,        // 46: .
    Char_id.C_FSLASH,     // 47: /
    Char_id.C_ZERO,       // 48: 0
    Char_id.C_ONE,        // 49: 1
    Char_id.C_OCT,        // 50: 2
    Char_id.C_OCT,        // 51: 3
    Char_id.C_OCT,        // 52: 4
    Char_id.C_OCT,        // 53: 5
    Char_id.C_OCT,        // 54: 6
    Char_id.C_OCT,        // 55: 7
    Char_id.C_DIGIT,      // 56: 8
    Char_id.C_DIGIT,      // 57: 9
    Char_id.C_PUNCT,      // 58: :
    Char_id.C_PUNCT,      // 59: ;
    Char_id.C_PUNCT,      // 60: <
    Char_id.C_PUNCT,      // 61: =
    Char_id.C_PUNCT,      // 62: >
    Char_id.C_PUNCT,      // 63: ?
    Char_id.C_PUNCT,      // 64: @
    Char_id.C_HEX,        // 65: a
    Char_id.C_B,          // 66: Char_id.C_HEX,
    Char_id.C_HEX,        // 67: c
    Char_id.C_HEX,        // 68: d
    Char_id.C_E,          // 69: e
    Char_id.C_HEX,        // 70: f
    Char_id.C_IDNT,       // 71: g
    Char_id.C_IDNT,       // 72: h
    Char_id.C_IDNT,       // 73: i
    Char_id.C_IDNT,       // 74: j
    Char_id.C_IDNT,       // 75: k
    Char_id.C_IDNT,       // 76: l
    Char_id.C_IDNT,       // 77: m
    Char_id.C_IDNT,       // 78: n
    Char_id.C_IDNT,       // 79: o
    Char_id.C_P,          // 80: 16
    Char_id.C_IDNT,       // 81: q
    Char_id.C_R,          // 82: r
    Char_id.C_IDNT,       // 83: s
    Char_id.C_IDNT,       // 84: t
    Char_id.C_IDNT,       // 85: u
    Char_id.C_IDNT,       // 86: v
    Char_id.C_IDNT,       // 87: w
    Char_id.C_X,          // 88: x
    Char_id.C_IDNT,       // 89: y
    Char_id.C_IDNT,       // 90: z
    Char_id.C_LOPEN,      // 91: [
    Char_id.C_BSLASH,     // 92: \ escape
    Char_id.C_RCLOSE,     // 93: ]
    Char_id.C_PUNCT,      // 94: ^
    Char_id.C_UNDERSCORE, // 95: _
    Char_id.C_PUNCT,      // 96: tkn_backtick,   // 32
    Char_id.C_HEX,        // 97: a (lowercase)
    Char_id.C_B,          // 98: b
    Char_id.C_HEX,        // 99: c
    Char_id.C_HEX,        // 100: d
    Char_id.C_E,          // 101: e
    Char_id.C_HEX,        // 102: f
    Char_id.C_IDNT,       // 103: g
    Char_id.C_IDNT,       // 104: h
    Char_id.C_IDNT,       // 105: i
    Char_id.C_IDNT,       // 106: j
    Char_id.C_IDNT,       // 107: k
    Char_id.C_IDNT,       // 108: l
    Char_id.C_IDNT,       // 109: m
    Char_id.C_IDNT,       // 110: n
    Char_id.C_IDNT,       // 111: o
    Char_id.C_P,          // 112: p 16
    Char_id.C_IDNT,       // 113: q
    Char_id.C_R,          // 114: r
    Char_id.C_IDNT,       // 115: s
    Char_id.C_IDNT,       // 116: t
    Char_id.C_IDNT,       // 117: u
    Char_id.C_IDNT,       // 118: v
    Char_id.C_IDNT,       // 119: w
    Char_id.C_X,          // 120: x
    Char_id.C_IDNT,       // 121: y
    Char_id.C_IDNT,       // 122: z
    Char_id.C_LOPEN,      // 123: {
    Char_id.C_PUNCT,      // 124: |
    Char_id.C_RCLOSE,     // 125: }
    Char_id.C_PUNCT,      // 126: ~
    Char_id.C_HSPACE,     // 127: del
    Char_id.C_CR1,        // 80: 64 128 - 255 non ascii characters
    Char_id.C_CR1,        // 81
    Char_id.C_CR1,        // 82
    Char_id.C_CR1,        // 83
    Char_id.C_CR1,        // 84
    Char_id.C_CR1,        // 85
    Char_id.C_CR1,        // 86
    Char_id.C_CR1,        // 87
    Char_id.C_CR1,        // 88
    Char_id.C_CR1,        // 89
    Char_id.C_CR1,        // 8A
    Char_id.C_CR1,        // 8B
    Char_id.C_CR1,        // 8C
    Char_id.C_CR1,        // 8D
    Char_id.C_CR1,        // 8E
    Char_id.C_CR1,        // 8F
    Char_id.C_CR1,        // 90
    Char_id.C_CR2,        // 91
    Char_id.C_CR2,        // 92
    Char_id.C_CR2,        // 93
    Char_id.C_CR2,        // 94
    Char_id.C_CR2,        // 95
    Char_id.C_CR2,        // 96
    Char_id.C_CR2,        // 97
    Char_id.C_CR2,        // 98
    Char_id.C_CR2,        // 99
    Char_id.C_CR2,        // 9A
    Char_id.C_CR2,        // 9B
    Char_id.C_CR2,        // 9C
    Char_id.C_CR2,        // 9D
    Char_id.C_CR2,        // 9E
    Char_id.C_CR2,        // 9F
    Char_id.C_CR2,        // A0
    Char_id.C_CR3,        // A1
    Char_id.C_CR3,        // A2
    Char_id.C_CR3,        // A3
    Char_id.C_CR3,        // A4
    Char_id.C_CR3,        // A5
    Char_id.C_CR3,        // A6
    Char_id.C_CR3,        // A7
    Char_id.C_CR3,        // A8
    Char_id.C_CR3,        // A9
    Char_id.C_CR3,        // AA
    Char_id.C_CR3,        // AB
    Char_id.C_CR3,        // AC
    Char_id.C_CR3,        // AD
    Char_id.C_CR3,        // AE
    Char_id.C_CR3,        // AF
    Char_id.C_CR3,        // B0
    Char_id.C_CR3,        // B1
    Char_id.C_CR3,        // B2
    Char_id.C_CR3,        // B3
    Char_id.C_CR3,        // B4
    Char_id.C_CR3,        // B5
    Char_id.C_CR3,        // B6
    Char_id.C_CR3,        // B7
    Char_id.C_CR3,        // B8
    Char_id.C_CR3,        // B9
    Char_id.C_CR3,        // BA
    Char_id.C_CR3,        // BB
    Char_id.C_CR3,        // BC
    Char_id.C_CR3,        // BD
    Char_id.C_CR3,        // BE
    Char_id.C_CR3,        // BF
    Char_id.C_CR3,        // C0
    Char_id.C_ILL,        // C1
    Char_id.C_ILL,        // C2
    Char_id.C_L2A,        // C3
    Char_id.C_L2A,        // C4
    Char_id.C_L2A,        // C5
    Char_id.C_L2A,        // C6
    Char_id.C_L2A,        // C7
    Char_id.C_L2A,        // C8
    Char_id.C_L2A,        // C9
    Char_id.C_L2A,        // CA
    Char_id.C_L2A,        // CB
    Char_id.C_L2A,        // CC
    Char_id.C_L2A,        // CD
    Char_id.C_L2A,        // CE
    Char_id.C_L2A,        // CF
    Char_id.C_L2A,        // D0
    Char_id.C_L2A,        // D1
    Char_id.C_L2A,        // D2
    Char_id.C_L2A,        // D3
    Char_id.C_L2A,        // D4
    Char_id.C_L2A,        // D5
    Char_id.C_L2A,        // D6
    Char_id.C_L2A,        // D7
    Char_id.C_L2A,        // D8
    Char_id.C_L2A,        // D9
    Char_id.C_L2A,        // DA
    Char_id.C_L2A,        // DB
    Char_id.C_L2A,        // DC
    Char_id.C_L2A,        // DD
    Char_id.C_L2A,        // DE
    Char_id.C_L2A,        // DF
    Char_id.C_L2A,        // E0
    Char_id.C_L3A,        // E1
    Char_id.C_L3B,        // E2
    Char_id.C_L3B,        // E3
    Char_id.C_L3B,        // E4
    Char_id.C_L3B,        // E5
    Char_id.C_L3B,        // E6
    Char_id.C_L3B,        // E7
    Char_id.C_L3B,        // E8
    Char_id.C_L3B,        // E9
    Char_id.C_L3B,        // EA
    Char_id.C_L3B,        // EB
    Char_id.C_L3B,        // EC
    Char_id.C_L3B,        // ED
    Char_id.C_L3C,        // EE
    Char_id.C_L3B,        // EF
    Char_id.C_L3B,        // F0
    Char_id.C_L4A,        // F1
    Char_id.C_L4B,        // F2
    Char_id.C_L4B,        // F3
    Char_id.C_L4B,        // F4
    Char_id.C_L4C,        // F5
    Char_id.C_ILL,        // F6
    Char_id.C_ILL,        // F7
    Char_id.C_ILL,        // F8
    Char_id.C_ILL,        // F9
    Char_id.C_ILL,        // FA
    Char_id.C_ILL,        // FB
    Char_id.C_ILL,        // FC
    Char_id.C_ILL,        // FD
    Char_id.C_ILL,        // FE
    Char_id.C_ILL         // 255 FF
};

const TrivialToken[] OPERATORS = {
    TrivialToken{"=", 1, Token_type.TKN_ASSIGN},
    TrivialToken{"==", 2, Token_type.TKN_EQ},
    TrivialToken{"~", 1, Token_type.TKN_BNOT},
    TrivialToken{"~=", 2, Token_type.TKN_BNOT_ASSIGN}, // not a c++ operator
    TrivialToken{"(", 1, Token_type.TKN_LPAREN},
    TrivialToken{"<", 1, Token_type.TKN_LT},
    TrivialToken{"<=", 2, Token_type.TKN_LTE},
    TrivialToken{"<=>", 3, Token_type.TKN_CMP},
    TrivialToken{"[", 1, Token_type.TKN_LBRACE},
    TrivialToken{"$", 1, Token_type.TKN_DOLLAR},
    TrivialToken{"}", 1, Token_type.TKN_RCURLY},
    TrivialToken{"<<", 2, Token_type.TKN_LSHIFT},
    TrivialToken{"<<=", 3, Token_type.TKN_LSHIFT_ASSIGN},
    TrivialToken{"@", 1, Token_type.TKN_AT},
    TrivialToken{"#", 1, Token_type.TKN_HASH},
    TrivialToken{">", 1, Token_type.TKN_GT},
    TrivialToken{">=", 2, Token_type.TKN_GTE},
    TrivialToken{"^", 1, Token_type.TKN_XOR},
    TrivialToken{"^=", 2, Token_type.TKN_XOR_ASSIGN},
    TrivialToken{"{", 1, Token_type.TKN_LCURLY},
    TrivialToken{"<>", 2, Token_type.TKN_CMP},
    TrivialToken{"/", 1, Token_type.TKN_DIV},
    TrivialToken{"/=", 2, Token_type.TKN_DIV_ASSIGN},
    TrivialToken{"|", 1, Token_type.TKN_BOR},
    TrivialToken{"|=", 2, Token_type.TKN_BOR_ASSIGN},
    TrivialToken{"+", 1, Token_type.TKN_ADD},
    TrivialToken{"+=", 2, Token_type.TKN_ADD_ASSIGN},
    TrivialToken{".", 1, Token_type.TKN_DOT},
    TrivialToken{">>", 2, Token_type.TKN_RSHIFT},
    TrivialToken{">>=", 3, Token_type.TKN_RSHIFT_ASSIGN},
    TrivialToken{"?", 1, Token_type.TKN_TERNARY},
    TrivialToken{"&", 1, Token_type.TKN_BAND},
    TrivialToken{"&=", 2, Token_type.TKN_BAND_ASSIGN},
    TrivialToken{"*", 1, Token_type.TKN_MUL},
    TrivialToken{"*=", 2, Token_type.TKN_MUL_ASSIGN},
    TrivialToken{"-", 1, Token_type.TKN_SUB},
    TrivialToken{"-=", 2, Token_type.TKN_SUB_ASSIGN},
    TrivialToken{"%", 2, Token_type.TKN_MOD},
    TrivialToken{"%=", 2, Token_type.TKN_MOD_ASSIGN},
    TrivialToken{":", 1, Token_type.TKN_COLON},
    TrivialToken{":=", 2, Token_type.TKN_DECL_ASSIGN}, // not a c++ operator
    TrivialToken{"!", 1, Token_type.TKN_LNOT},
    TrivialToken{"!=", 2, Token_type.TKN_NEQ},
    TrivialToken{"`", 1, Token_type.TKN_BACKTICK},
    TrivialToken{"||", 2, Token_type.TKN_LOR},
    TrivialToken{"||=", 3, Token_type.TKN_LOR_ASSIGN},
    TrivialToken{";", 1, Token_type.TKN_SEMICOLON},
    TrivialToken{"++", 2, Token_type.TKN_PREFIX_INC},
    TrivialToken{"->", 2, Token_type.TKN_ARROW},
    TrivialToken{`\`, 1, Token_type.TKN_BACKSLASH},
    TrivialToken{",", 1, Token_type.TKN_COMMA},
    TrivialToken{"]", 1, Token_type.TKN_RBRACE},
    TrivialToken{"..", 2, Token_type.TKN_RANGE},
    TrivialToken{"...", 3, Token_type.TKN_ELLIPSIS},
    TrivialToken{")", 1, Token_type.TKN_RPAREN},
    TrivialToken{"&&", 2, Token_type.TKN_LAND},
    TrivialToken{"&&=", 3, Token_type.TKN_LAND_ASSIGN},
    TrivialToken{"--", 2, Token_type.TKN_PREFIX_DEC},
    TrivialToken{"::", 2, Token_type.TKN_SCOPE}
};

enum Keyword_type : char {
    KW_START,
    KW_ALIGNAS,
    KW_ALIGNOF,
    KW_OFFSETOF,
    KW_SIZEOF,
    KW_TYPEOF,
    // LOGICAL
    KW_AND,
    KW_OR,
    KW_XOR,
    KW_NOT,
    //"BI KW_BITAND,
    //{"B KW_BITOR,
    // TYPES
    KW_AUTO,
    KW_U64,
    KW_U32,
    KW_U16,
    KW_U8,

    KW_I64,
    KW_I32,
    KW_I16,
    KW_I8,

    KW_C64,
    KW_C32,
    KW_C16,
    KW_C8,

    KW_SHORT,
    KW_INT,
    KW_LONG,
    KW_CHAR,
    KW_BYTE,

    KW_FLOAT,
    KW_DOUBLE,
    KW_FLT,
    KW_DBL,

    KW_VOID,
    // FLOW CONTROL
    KW_RETURN,
    KW_WHILE,
    KW_DO,
    KW_FOR,
    KW_CONTINUE,
    KW_BREAK,
    KW_SWITCH,
    KW_CASE,
    KW_DEFAULT,
    KW_IF,
    KW_ELSE,
    KW_TRY,
    KW_THROW,
    KW_CATCH,
    KW_GOTO,
    // LOW LEVEL
    KW_ASM,
    // COMPILE TIME
    KW_CONSTEXPR,
    KW_CONSTINIT,
    // STRUCTS
    KW_CLASS,
    KW_STRUCT,
    KW_UNION,
    KW_ENUM,
    // GENERAL TYPING
    KW_TYPE,
    // PRIVACY KEYWORDS
    KW_PRIVATE,
    KW_PROTECTED,
    KW_PUBLIC,
    KW_FRIEND,
    // SPECIFIERS
    KW_CONST,
    KW_HARD_CONST, //IMMUTABLE KEYWORD
    KW_MUTABLE,
    KW_VOLATILE,
    KW_INLINE,
    KW_VIRTUAL,
    KW_SIGNED,
    KW_UNSIGNED,
    KW_STATIC,
    // INCLUDES
    KW_INCLUDE,
    KW_IMPORT,
    KW_EMBED,
    // EXPORT
    KW_EXPORT,
    // CONSTANTS
    KW_TRUE,
    KW_FALSE,
    KW_NULL,
    KW__SIZE
}

const TrivialToken[] KEYWORDS =  {
    // meta information
    TrivialToken{"alignas", 7, Keyword_type.KW_ALIGNAS},
    TrivialToken{"alignof", 7, Keyword_type.KW_ALIGNOF},
    TrivialToken{"offsetof", 8, Keyword_type.KW_OFFSETOF},
    TrivialToken{"sizeof", 6, Keyword_type.KW_SIZEOF},
    TrivialToken{"typeof", 6, Keyword_type.KW_TYPEOF},
    // logical
    TrivialToken{"and", 3, Keyword_type.KW_AND},
    TrivialToken{"or", 2, Keyword_type.KW_OR},
    TrivialToken{"xor", 3, Keyword_type.KW_XOR},
    TrivialToken{"not", 3, Keyword_type.KW_NOT},
    // TrivialToken{"bitand", 6, Keyword_type.kw_bitand},
    // TrivialToken{"bitor", 5, Keyword_type.kw_bitor},
    // types
    TrivialToken{"auto", 4, Keyword_type.KW_AUTO},
    TrivialToken{"u64", 3, Keyword_type.KW_U64},
    TrivialToken{"u32", 3, Keyword_type.KW_U32},
    TrivialToken{"u16", 3, Keyword_type.KW_U16},
    TrivialToken{"u8", 2, Keyword_type.KW_U8},

    TrivialToken{"i64", 3, Keyword_type.KW_I64},
    TrivialToken{"i32", 3, Keyword_type.KW_I32},
    TrivialToken{"i16", 3, Keyword_type.KW_I16},
    TrivialToken{"i8", 2, Keyword_type.KW_I8},

    TrivialToken{"c64", 3, Keyword_type.KW_C64},
    TrivialToken{"c32", 3, Keyword_type.KW_C32},
    TrivialToken{"c16", 3, Keyword_type.KW_C16},
    TrivialToken{"c8", 2, Keyword_type.KW_C8},

    TrivialToken{"short", 5, Keyword_type.KW_SHORT},
    TrivialToken{"int", 3, Keyword_type.KW_INT},
    TrivialToken{"long", 4, Keyword_type.KW_LONG},
    TrivialToken{"char", 4, Keyword_type.KW_CHAR},
    TrivialToken{"byte", 4, Keyword_type.KW_BYTE},

    TrivialToken{"float", 5, Keyword_type.KW_FLOAT},
    TrivialToken{"double", 6, Keyword_type.KW_DOUBLE},
    TrivialToken{"flt", 3, Keyword_type.KW_FLT},
    TrivialToken{"dbl", 3, Keyword_type.KW_DBL},

    TrivialToken{"void", 4, Keyword_type.KW_VOID},
    // flow control
    TrivialToken{"return", 6, Keyword_type.KW_RETURN},
    TrivialToken{"while", 5, Keyword_type.KW_WHILE},
    TrivialToken{"do", 2, Keyword_type.KW_DO},
    TrivialToken{"for", 3, Keyword_type.KW_FOR},
    TrivialToken{"continue", 8, Keyword_type.KW_CONTINUE},
    TrivialToken{"break", 5, Keyword_type.KW_BREAK},
    TrivialToken{"switch", 6, Keyword_type.KW_SWITCH},
    TrivialToken{"case", 4, Keyword_type.KW_CASE},
    TrivialToken{"default", 7, Keyword_type.KW_DEFAULT},
    TrivialToken{"if", 2, Keyword_type.KW_IF},
    TrivialToken{"else", 4, Keyword_type.KW_ELSE},
    TrivialToken{"try", 3, Keyword_type.KW_TRY},
    TrivialToken{"throw", 5, Keyword_type.KW_THROW},
    TrivialToken{"catch", 5, Keyword_type.KW_CATCH},
    TrivialToken{"goto", 4, Keyword_type.KW_GOTO},
    // low level
    TrivialToken{"asm", 3, Keyword_type.KW_ASM},
    // compile time
    TrivialToken{"constexpr", 9, Keyword_type.KW_CONSTEXPR},
    TrivialToken{"constinit", 9, Keyword_type.KW_CONSTINIT},
    // structs
    TrivialToken{"class", 5, Keyword_type.KW_CLASS},
    TrivialToken{"struct", 6, Keyword_type.KW_STRUCT},
    TrivialToken{"union", 5, Keyword_type.KW_UNION},
    TrivialToken{"enum", 4, Keyword_type.KW_ENUM},
    //
    TrivialToken{"type", 4, Keyword_type.KW_TYPE},
    //
    TrivialToken{"private", 7, Keyword_type.KW_PRIVATE},
    TrivialToken{"protected", 9, Keyword_type.KW_PROTECTED},
    TrivialToken{"public", 6, Keyword_type.KW_PUBLIC},
    TrivialToken{"friend", 6, Keyword_type.KW_FRIEND},
    // specifiers
    TrivialToken{"const", 5, Keyword_type.KW_CONST},
    TrivialToken{"hard_const", 10, Keyword_type.KW_HARD_CONST},
    TrivialToken{"mutable", 7, Keyword_type.KW_MUTABLE},
    TrivialToken{"volatile", 8, Keyword_type.KW_VOLATILE},
    TrivialToken{"inline", 6, Keyword_type.KW_INLINE},
    TrivialToken{"virtual", 6, Keyword_type.KW_VIRTUAL},
    TrivialToken{"signed", 6, Keyword_type.KW_SIGNED},
    TrivialToken{"unsigned", 8, Keyword_type.KW_UNSIGNED},
    TrivialToken{"static", 6, Keyword_type.KW_STATIC},
    // includes
    TrivialToken{"include", 7, Keyword_type.KW_INCLUDE},
    TrivialToken{"import", 6, Keyword_type.KW_IMPORT},
    TrivialToken{"embed", 5, Keyword_type.KW_EMBED},
    // exports
    TrivialToken{"export", 6, Keyword_type.KW_EXPORT},
    // constants
    TrivialToken{"true", 4, Keyword_type.KW_TRUE},
    TrivialToken{"false", 5, Keyword_type.KW_FALSE},
    TrivialToken{"null", 4, Keyword_type.KW_NULL}
};

const TrivialToken[] OPERATOR_MAP = {
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"/",1,Token_type.TKN_DIV},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{".",1,61},
    TrivialToken{">>=",3,26},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"-",1,43},
    TrivialToken{"`",1,78},
    TrivialToken{"/=",2,Token_type.TKN_DIV_ASSIGN},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{",",1,11},
    TrivialToken{"",0,0},
    TrivialToken{"<=>",3,39},
    TrivialToken{"->",2,81},
    TrivialToken{"",0,0},
    TrivialToken{"+",1,42},
    TrivialToken{"^",1,31},
    TrivialToken{"-=",2,15},
    TrivialToken{"",0,0},
    TrivialToken{"<<=",3,25},
    TrivialToken{"*",1,44},
    TrivialToken{"]",1,68},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{")",1,66},
    TrivialToken{`\`,1,76},
    TrivialToken{"+=",2,14},
    TrivialToken{"^=",2,19},
    TrivialToken{"",0,0},
    TrivialToken{"(",1,63},
    TrivialToken{"[",1,65},
    TrivialToken{"*=",2,16},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"&",1,32},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"%",1,46},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"$",1,74},
    TrivialToken{"",0,0},
    TrivialToken{"&=",2,23},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"#",1,71},
    TrivialToken{"",0,0},
    TrivialToken{"%=",2,18},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"!",1,49},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"..",2,82},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"!=",2,34},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"--",2,53},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"++",2,52},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"~",1,48},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"}",1,67},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"|",1,30},
    TrivialToken{"",0,0},
    TrivialToken{"~=",2,21},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"{",1,64},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"|=",2,20},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"||",2,28},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"&&",2,29},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"@",1,75},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"?",1,27},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{">",1,35},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"=",1,13},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{">>",2,40},
    TrivialToken{"",0,0},
    TrivialToken{"<",1,37},
    TrivialToken{"",0,0},
    TrivialToken{">=",2,36},
    TrivialToken{"",0,0},
    TrivialToken{"...",3,83},
    TrivialToken{";",1,70},
    TrivialToken{"",0,0},
    TrivialToken{"==",2,33},
    TrivialToken{"<>",2,39},
    TrivialToken{"",0,0},
    TrivialToken{":",1,69},
    TrivialToken{"",0,0},
    TrivialToken{"<=",2,38},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"<<",2,41},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{":=",2,12},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"||=",3,22},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"&&=",3,24},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"::",2,62},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0},
    TrivialToken{"",0,0}
};

fn bool is_second_idnt(char c) {
    return ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_'));
}

fn bool is_any_newline(char c) {
    return c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

fn bool is_eof(char c) {
    // eof 0 and subeof 26
    return c == 0 || c == 26;
}

fn uint symbol_hash(char *ptr, uint len) @inline {
    uint h       = 0;
    uint max_len = len & 0x3; // symbols are at most 3 in length
    // note 251 is the 50 something ish prime
    for (uint i = 0; i < max_len; i++) {
        h += (uint)ptr[i] * (i + 251);
    }
    return h &= 0xff;
}

fn bool is_newline_codepoint(uint codepoint) @inline {
    return (codepoint == 0x00_00_24_24 || // newline
        codepoint == 0x00_00_2B_92 || //newline left
        codepoint == 0x00_00_2B_93 || //newline right
        codepoint == 0x00_00_00_0A || //line feed \n
        codepoint == 0x00_00_00_85 || //next line NEL
        codepoint == 0x00_00_24_0A || //line feed symbol
        codepoint == 0x00_00_21_85 || //downwards arrow
        codepoint == 0x00_00_23_CE || //return symbol
        codepoint == 0x00_00_24_0D || //carriage return) \r
        codepoint == 0x00_00_00_0C  // form feed \f
    );
}

fn bool is_newline_ascii(char c) @inline {
    return c == '\n' || c == '\r' || c == '\f';
}

fn char* find_next_newline(char *buf) @inline {
    uint state = 0;
    uint codepoint = 0;

    while (*buf) {
        uint t = utf8_decode::decode(&state, &codepoint, *buf);
        if ((t == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) || t == utf8_decode::UTF8_REJECT) { 
            break;
        }
        buf++;
    }

    return buf;
}

fn void scan_nothing(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    return;
} 
//started with 0
fn void scan_base2_number_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_INTEGER});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset + 1;
    usize val = 0;
    usize dot_offset = 0;

    if (src.entries[i] == 'x' || src.entries[i] == 'X') {
        i += 1;

        for (;i < src.size; i++) {
            char c = src.entries[i];
            if (c == '_') {
                continue;
            }
            uint digit = CHAR_TO_DIGIT[c];
            if (digit >= 16) {
                break;
            }
            val = (val * 16) + digit;
            dot_offset += 1;
        }
        // handle hex floats?
    } else if (src.entries[i] == 'b' || src.entries[i] == 'B') {
        i += 1;

        for (;i < src.size; i++) {
            char c = src.entries[i];
            if (c == '_') {
                continue;
            }
            uint digit = CHAR_TO_DIGIT[c];
            if (digit >= 2) {
                break;
            }
            val = (val * 2) + digit;
            dot_offset += 1;
        }
        // handle binary floats?
    } else if (src.entries[i] >= '0' || src.entries[i] <= '7') {

        for (;i < src.size; i++) {
            char c = src.entries[i];
            if (c == '_') {
                continue;
            }
            uint digit = CHAR_TO_DIGIT[c];
            if (digit >= 8) {
                break;
            }
            val = (val * 8) + digit;
            dot_offset += 1;
        }
    }

    data.entries[tnext].first.u64 = val;
    info.entries[tnext].length = i-current.offset;

    current.col += (int)(i-current.offset);
    current.offset = i;
} 

fn void scan_number_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_INTEGER});
    info.push(*current);
    data.push(TokenData{});

    isize dot_offset = 0;
    usize val = CHAR_TO_DIGIT[src.entries[current.offset]];

    usize i = current.offset+1;

    for (;i < src.size; i++) {
        char c = src.entries[i];
        if (c == '_') {
            continue;
        }
        uint digit = CHAR_TO_DIGIT[c];
        if (digit >= 10) {
            break;
        }
        val = (val * 10) + digit;
        //dot_offset += 1;
    }

    if (i < src.size && src.entries[i] == '.') {
        i++;
        tokens.entries[tnext].tid = Token_type.TKN_FLOAT;
        for (;i < src.size; i++) {
            char c = src.entries[i];
            if (c == '_') {
                continue;
            }
            uint digit = CHAR_TO_DIGIT[c];
            if (digit >= 10) {
                break;
            }
            val = (val * 10) + digit;
            dot_offset -= 1;
        }
    }

    if (i < src.size && (src.entries[i] == 'e' || src.entries[i] == 'E')) {
        i++;
        tokens.entries[tnext].tid = Token_type.TKN_FLOAT;
        bool is_negative = (i < src.size && src.entries[i] == '-');
        i += (usize)(i < src.size && (src.entries[i] == '-' || src.entries[i] == '+'));
        isize exponent = 0;

        for (;i < src.size; i++) {
            char c = src.entries[i];
            if (c == '_') {
                continue;
            }
            uint digit = CHAR_TO_DIGIT[c];
            if (digit >= 10) {
                break;
            }
            //val = (val * 10) + digit;
            //dot_offset += 1;
            exponent = (exponent * 10) + digit;
        }
        exponent *= is_negative ? -1 : 1;
        dot_offset += exponent;
        //dot_offset *= is_negative ? -1 : 1;
    }
    //mantissa * 10^dot_offset
    data.entries[tnext].first.u64 = val;
    data.entries[tnext].second.i64 = dot_offset;

    info.entries[tnext].length = (i-current.offset);

    current.col += (int)(i-current.offset);
    current.offset = i;
} 

fn void scan_identifier_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {    
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_IDENTIFIER});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset;
    for(;is_second_idnt(src.entries[i]); i++) {
        
    }

    data.entries[tnext].first.u64 = wheathash::wheathash(&src.entries[i], (uint)(i-current.offset), 0);

    info.entries[tnext].length = i-current.offset;
    // bump current towards next thing
    current.col += (int)(i-current.offset);
    current.offset = i;
} 

fn void scan_newline_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_VSPACE});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset;
    i = (i+1) + (usize)((i+1) < src.size && (src.entries[i] == '\r') && (src.entries[i+1] == '\n'));
    //char *next_newline = find_next_newline(&src.entries[current.offset]);
    //usize i = (next_newline - &src.entries[0]);

    info.entries[tnext].length = i-current.offset;
    //info.entries[tnext].line += 1;
    //info.entries[tnext].col = 0;
    
    //info.entries[tnext].col    = current.col;
    //info.entries[tnext].line   = current.line;
    // bump current towards next thing
    current.line += 1;
    current.col = 0;
    current.offset = i;
} 

fn void scan_discard_newline_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize i = current.offset;
    i = (i+1) + (usize)((i+1) < src.size && (src.entries[i] == '\r') && (src.entries[i+1] == '\n'));

    // bump current towards next thing
    current.line += 1;
    current.col = 0;
    current.offset = i;
} 

// starts with /
fn void scan_comment_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_DIV});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset;

    if ((i+1) < src.size && src.entries[i+1] == '/') {
        i+=2;
        tokens.entries[tnext].tid = Token_type.TKN_WHITESPACE;
        
        char* buf = &src.entries[i];

        uint state = 0;
        uint codepoint = 0;
        while (*buf) {
            uint v = utf8_decode::decode(&state, &codepoint, *buf);
            if ((v == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) || v == utf8_decode::UTF8_REJECT) { 
                break;
            }
            buf++;
            i++;
        }
        
        info.entries[tnext].length = (i-current.offset);

        current.offset = i;
    } else if ((i+1) < src.size && src.entries[i+1] == '*') {
        i+=2;
        tokens.entries[tnext].tid = Token_type.TKN_WHITESPACE;

        uint state = 0;
        uint codepoint = 0;

        bool normal_exit = false;
        for (;(i+1) < src.size;i++) {
            char* buf = &src.entries[i];
            if (libc::memcmp("*/",buf,2) == 0) {
                i+=2;
                normal_exit = true;
                break;
            }

            uint v = utf8_decode::decode(&state, &codepoint, *buf);
            if (v == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) { 
                current.line++;
                current.col=0;
            } else {
                current.col++;
            }
        }
        i = normal_exit ? i : src.size;

        info.entries[tnext].length = (i-current.offset);

        current.offset = i;
    } else if ((i+1) < src.size && src.entries[i+1] == '=') {
        i+=2;
        tokens.entries[tnext].tid = Token_type.TKN_DIV_ASSIGN;


        info.entries[tnext].length = (i-current.offset);

        current.offset = i;
    } else {
        i++;

        info.entries[tnext].length = (i-current.offset);

        current.offset = i;
    }
} 

fn void scan_discard_comment_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    usize i = current.offset;

    if ((i+1) < src.size && src.entries[i+1] == '/') {
        i+=2;

        char* buf = &src.entries[i];

        uint state = 0;
        uint codepoint = 0;
        while (*buf) {
            uint v = utf8_decode::decode(&state, &codepoint, *buf);
            if ((v == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) || v == utf8_decode::UTF8_REJECT) { 
                break;
            }
            buf++;
            i++;
        }

        current.offset = i;
    } else if ((i+1) < src.size && src.entries[i+1] == '*') {
        i+=2;

        uint state = 0;
        uint codepoint = 0;

        bool normal_exit = false;
        for (;(i+1) < src.size;i++) {
            char* buf = &src.entries[i];
            if (libc::memcmp("*/",buf,2) == 0) {
                i+=2;
                normal_exit = true;
                break;
            }

            uint v = utf8_decode::decode(&state, &codepoint, *buf);
            if (v == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) { 
                current.line++;
                current.col=0;
            } else {
                current.col++;
            }
        }
        i = normal_exit ? i : src.size;

        current.offset = i;
    } else if ((i+1) < src.size && src.entries[i+1] == '=') {
        tokens.push(Token{Token_type.TKN_DIV_ASSIGN});
        info.push(*current);
        data.push(TokenData{});

        i+=2;
        info.entries[tnext].length = (i-current.offset);
        current.offset = i;
    } else {
        tokens.push(Token{Token_type.TKN_DIV});
        info.push(*current);
        data.push(TokenData{});

        i++;
        info.entries[tnext].length = (i-current.offset);
        current.offset = i;
    }
} 

fn void scan_error_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    return;
}

fn void scan_utf8_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_DIV});
    info.push(*current);
    data.push(TokenData{});

    char *buf = &src.entries[current.offset];
    uint state = 0;
    uint codepoint = 0;

    while (*buf) {
        uint t = utf8_decode::decode(&state, &codepoint, *buf);
        if (t == utf8_decode::UTF8_ACCEPT &&
        (codepoint <= 0x00_00_00_7f
        ) || t == utf8_decode::UTF8_REJECT
        ) {
            break;
        }
        buf++;
    }

    usize i = (buf - src.entries);
    info.entries[tnext].length = (i-current.offset);

    current.offset = i;
}

fn void scan_operator_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_DIV});
    info.push(*current);
    data.push(TokenData{});

    usize remaining_chars = (current.offset < src.size) ? src.size-current.offset : 0;
    //printf("rem_chars: %i\n", remaining_chars);

    switch (remaining_chars) {
    default:
        nextcase;
    case 3:
        uint hash3 = symbol_hash(&src.entries[current.offset],3);
        TrivialToken op = OPERATOR_MAP[hash3];
        //printf("hash3: %i {\"%s\",%i,%i}\n", hash3, op.ptr, op.sz, op.id);
        if (op.sz == 3 && libc::memcmp(op.ptr, &src.entries[current.offset], 3) == 0) {
            tokens.entries[tnext].id = op.id;
            info.entries[tnext].length = 3;
            current.offset += 3;
            current.col += 3;
            return;
        }
        nextcase;
    case 2:
        uint hash2 = symbol_hash(&src.entries[current.offset],2);
        TrivialToken op = OPERATOR_MAP[hash2];
        //printf("hash2: %i {\"%s\",%i,%i}\n", hash2, op.ptr, op.sz, op.id);
        if (op.sz == 2 && libc::memcmp(op.ptr, &src.entries[current.offset], 2) == 0) {
            tokens.entries[tnext].id = op.id;
            info.entries[tnext].length = 2;
            current.offset += 2;
            current.col += 2;
            return;
        }
        nextcase;
    case 1:
        uint hash1 = symbol_hash(&src.entries[current.offset],1);
        TrivialToken op = OPERATOR_MAP[hash1];
        //printf("hash1: %i {\"%s\",%i,%i}\n", hash1, op.ptr, op.sz, op.id);

        tokens.entries[tnext].id = op.id;
        info.entries[tnext].length = 1;
        current.offset += 1;
        current.col += 1;
        return;
    case 0:
        //should be unreachable
        tokens.entries[tnext].id = Token_type.TKN__SIZE;
        info.entries[tnext].length = 1;
        current.offset += 1;
        current.col += 1;
        return;
    }
} 

fn void scan_dot_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_DOT});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset + 1;

    usize val = 0;
    isize dot_offset = 0;
    bool is_floating_point = false;
    // might be floating point
    for (;i < src.size; i++) {
        char c = src.entries[i];
        if (c == '_') {
            continue;
        }
        uint digit = CHAR_TO_DIGIT[c];
        if (digit >= 10) {
            break;
        }
        is_floating_point = true;
        val = (val * 10) + digit;
        dot_offset -= 1;
    }

    if (is_floating_point) {
        tokens.entries[tnext].tid = Token_type.TKN_FLOAT;
        if (i < src.size && (src.entries[i] == 'e' || src.entries[i] == 'E')) {
            i++;
            bool is_negative = (i < src.size && src.entries[i] == '-');
            i += (usize)(i < src.size && (src.entries[i] == '-' || src.entries[i] == '+'));
            isize exponent = 0;

            for (;i < src.size; i++) {
                char c = src.entries[i];
                if (c == '_') {
                    continue;
                }
                uint digit = CHAR_TO_DIGIT[c];
                if (digit >= 10) {
                    break;
                }
                //val = (val * 10) + digit;
                //dot_offset += 1;
                exponent = (exponent * 10) + digit;
            }
            exponent *= is_negative ? -1 : 1;
            dot_offset += exponent;
            //dot_offset *= is_negative ? -1 : 1;
        }
    }

    i = is_floating_point ? i : current.offset+1;
    
    info.entries[tnext].length = (i-current.offset);

    data.entries[tnext].first.u64 = val;
    data.entries[tnext].second.i64 = dot_offset;

    current.col += (int)(i-current.offset);
    current.offset = i;
} 

fn void scan_raw_string_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize i = current.offset;
    if ((i+1) < src.size && src.entries[i+1] == '"') {
        usize tnext = tokens.size;
        tokens.push(Token{Token_type.TKN_RSTRING});
        info.push(*current);
        data.push(TokenData{});

        i+=2;

        /*
        isize[256] boyer_moore_delta = {0};
        for () {

        }
        */
        info.entries[tnext].length = (i-current.offset);

    } else {
        scan_identifier_primed(tokens, info, data, src, current);
    }
} 

fn void scan_string_like_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current, Token_type as_token, char delim_char) {
    usize tnext = tokens.size;
    tokens.push(Token{as_token});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset;
    bool escaped = false;

    char *buf = &src.entries[current.offset];
    uint state = 0;
    uint codepoint = 0;

    for(;i < src.size; i++) {
        if (!escaped && src.entries[i] == delim_char) {
            i++;
            break;
        } else if (src.entries[i] == '\\') {
            escaped = !escaped;
        } else {
            escaped = false;
        }

        uint v = utf8_decode::decode(&state, &codepoint, *buf);
        if (v == utf8_decode::UTF8_ACCEPT && is_newline_codepoint(codepoint)) {
            current.line++;
            current.col=0;
        } else {
            current.col++;
        }
    }

    usize len = i-current.offset;
    info.entries[tnext].length = len;
    data.entries[tnext].first.u64 = wheathash::wheathash(&src.entries[i], (uint)len, 0);


    //info.entries[tnext].col    = current.col;
    //info.entries[tnext].line   = current.line;
    // bump current towards next thing
    current.offset = i;
}

fn void scan_squote_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    scan_string_like_primed(tokens, info, data, src, current, Token_type.TKN_CHARACTER, '\'');
} 

fn void scan_dquote_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    scan_string_like_primed(tokens, info, data, src, current, Token_type.TKN_STRING, '"');
} 

fn void scan_whitespace_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize tnext = tokens.size;
    tokens.push(Token{Token_type.TKN_WHITESPACE});
    info.push(*current);
    data.push(TokenData{});

    usize i = current.offset;
    for (;i < src.size; i++) {
        char chr = src.entries[i];
        if (chr == 0 || chr == 26 || chr > ' ') {
            break;
        }

        if (is_newline_codepoint(chr)) {
            current.line++;
            current.col=0;
        } else {
            current.col++;
        }
    }

    usize len = i-current.offset;
    info.entries[tnext].length = len;

    current.offset = i;
}

fn void scan_discard_whitespace_primed(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src, TokenInfo *current) {
    usize i = current.offset;
    for (;i < src.size; i++) {
        char chr = src.entries[i];
        if (chr == 0 || chr == 26 || chr > ' ') {
            break;
        }

        if (is_newline_codepoint(chr)) {
            current.line++;
            current.col=0;
        } else {
            current.col++;
        }
    }

    usize len = i-current.offset;
    current.offset = i;
}

ScanCallback[] tokenize_handlers = {
    &scan_nothing, //C_START
    &scan_base2_number_primed, //C_ZERO

    &scan_number_primed, //C_ONE
    &scan_number_primed, //C_OCT
    &scan_number_primed, //C_DIGIT

    &scan_identifier_primed, //C_HEX
    &scan_identifier_primed, //C_UNDERSCORE
    &scan_identifier_primed, //C_IDNT

    &scan_newline_primed, //C_CR
    &scan_newline_primed, //C_LN
    &scan_newline_primed, //C_LINE

    &scan_comment_primed, //C_FSLASH
    &scan_error_primed, //C_BSLASH

    &scan_operator_primed, //C_ADD
    &scan_operator_primed, //C_SUB

    &scan_dot_primed, //C_DOT
    &scan_operator_primed, //C_STAR

    &scan_identifier_primed, //C_X
    &scan_identifier_primed, //C_B
    &scan_raw_string_primed, //C_R
    &scan_identifier_primed, //C_E
    &scan_identifier_primed, //C_P

    &scan_squote_primed, //C_SQUOTE
    &scan_dquote_primed, //C_DQUOTE

    &scan_whitespace_primed, //C_HSPACE

    &scan_operator_primed, //C_PUNCT
    &scan_operator_primed, //C_LOPEN
    &scan_operator_primed, //C_RCLOSE

    &scan_utf8_primed, //C_UTF8
    &scan_utf8_primed, //C_CR1
    &scan_utf8_primed, //C_CR2
    &scan_utf8_primed, //C_CR3
    &scan_utf8_primed, //C_L2A
    &scan_utf8_primed, //C_L3A
    &scan_utf8_primed, //C_L3B
    &scan_utf8_primed, //C_L3C
    &scan_utf8_primed, //C_L4A
    &scan_utf8_primed, //C_L4B
    &scan_utf8_primed, //C_L4C
    &scan_utf8_primed  //C_ILL
};

ScanCallback[] tokenize_discard_whitespace_handlers = {
    &scan_nothing, //C_START
    &scan_base2_number_primed, //C_ZERO

    &scan_number_primed, //C_ONE
    &scan_number_primed, //C_OCT
    &scan_number_primed, //C_DIGIT

    &scan_identifier_primed, //C_HEX
    &scan_identifier_primed, //C_UNDERSCORE
    &scan_identifier_primed, //C_IDNT

    &scan_discard_newline_primed, //C_CR
    &scan_discard_newline_primed, //C_LN
    &scan_discard_newline_primed, //C_LINE

    &scan_discard_comment_primed, //C_FSLASH
    &scan_error_primed, //C_BSLASH

    &scan_operator_primed, //C_ADD
    &scan_operator_primed, //C_SUB

    &scan_dot_primed, //C_DOT
    &scan_operator_primed, //C_STAR

    &scan_identifier_primed, //C_X
    &scan_identifier_primed, //C_B
    &scan_raw_string_primed, //C_R
    &scan_identifier_primed, //C_E
    &scan_identifier_primed, //C_P

    &scan_squote_primed, //C_SQUOTE
    &scan_dquote_primed, //C_DQUOTE

    &scan_discard_whitespace_primed, //C_HSPACE

    &scan_operator_primed, //C_PUNCT
    &scan_operator_primed, //C_LOPEN
    &scan_operator_primed, //C_RCLOSE

    &scan_utf8_primed, //C_UTF8
    &scan_utf8_primed, //C_CR1
    &scan_utf8_primed, //C_CR2
    &scan_utf8_primed, //C_CR3
    &scan_utf8_primed, //C_L2A
    &scan_utf8_primed, //C_L3A
    &scan_utf8_primed, //C_L3B
    &scan_utf8_primed, //C_L3C
    &scan_utf8_primed, //C_L4A
    &scan_utf8_primed, //C_L4B
    &scan_utf8_primed, //C_L4C
    &scan_utf8_primed  //C_ILL
};

//TODO: make faster!
fn TokenizeStatus tokenize(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src) {
    TokenizeStatus ret = TokenizeStatus.OK;

    TokenInfo current_info;
    TokenInfo* position = &current_info;

    Token tkn;

    char[][] char_id_names = enum_names(Char_id);
    char[][] token_type_names = enum_names(Token_type);

    usize last_sz = info.size;

    for (current_info.offset = 0; current_info.offset < src.size;) {
        Char_id id = CHAR_ID_TABLE[src.entries[current_info.offset]];
        if (id < tokenize_handlers.len) {
            TokenInfo prev = current_info;
            tokenize_handlers[id](tokens, info, data, src, position);
            
            //printf("tkn (%i,%s):{%.*s}\n", (int)id, char_id_names[(int)id].ptr, (int)(current_info.offset-prev.offset), &src.entries[prev.offset]);

            if (last_sz != info.size) {
                //i += info.entries[last_sz].length;
                last_sz = info.size;
            } else if (prev.offset == current_info.offset) {
                // nothing tokenized (should be impossible)
                ret = TokenizeStatus.ZERO_LENGTH_TOKEN;
                break;
            } else {
                ret = TokenizeStatus.NO_NEW_TOKEN;
                break;
            }
        } else {
            // can't tokenize something
            ret = TokenizeStatus.INVALID_CHAR_ID;
            break;
        }
    }
    /*
    for (usize i = 0; i < tokens.size; i++) {
        printf("rtkn (%i,%s): {%.*s}\n", (int)tokens.entries[i].tid, token_type_names[(int)tokens.entries[i].tid].ptr, info.entries[i].length, &src.entries[info.entries[i].offset]);
    }
    */

    return ret;
}

fn TokenizeStatus tokenize_without_whitespace(TokenList *tokens, TokenInfoList *info, TokenDataList *data, Source *src) {
    TokenizeStatus ret = TokenizeStatus.OK;

    TokenInfo current_info;
    TokenInfo* position = &current_info;

    Token tkn;

    char[][] char_id_names = enum_names(Char_id);
    char[][] token_type_names = enum_names(Token_type);

    usize last_sz = info.size;

    for (current_info.offset = 0; current_info.offset < src.size;) {
        Char_id id = CHAR_ID_TABLE[src.entries[current_info.offset]];
        if (id < tokenize_handlers.len) {
            TokenInfo prev = current_info;
            tokenize_discard_whitespace_handlers[id](tokens, info, data, src, position);
            
            //printf("tkn (%i,%s):{%.*s}\n", (int)id, char_id_names[(int)id].ptr, (int)(current_info.offset-prev.offset), &src.entries[prev.offset]);

            if (last_sz != info.size) {
                //i += info.entries[last_sz].length;
                last_sz = info.size;
            } else if (prev.offset == current_info.offset) {
                // nothing tokenized (should be impossible)
                ret = TokenizeStatus.ZERO_LENGTH_TOKEN;
                break;
            }
        } else {
            // can't tokenize something
            ret = TokenizeStatus.INVALID_CHAR_ID;
            break;
        }
    }
    /*
    for (usize i = 0; i < tokens.size; i++) {
        printf("rtkn (%i,%s): {%.*s}\n", (int)tokens.entries[i].tid, token_type_names[(int)tokens.entries[i].tid].ptr, info.entries[i].length, &src.entries[info.entries[i].offset]);
    }
    */

    return ret;
}