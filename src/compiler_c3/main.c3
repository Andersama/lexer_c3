module compiler_c3;
import std::array::list;
import std::io;
import lexer;
import utf8_decode;
import std::math;

extern fn void printf(char*, ...);

/**
 * @require $Type.kind == TypeKind.ENUM `Only enums may be used`
 **/
macro enum_names($Type) @builtin
{
    typeid x = $Type.typeid;
    return x.names;
}

/*
fn int print_error(char[] filename, uint line, uint col, char[] fmt, ) {
    printf("(%.*s:%i:%i)", filename.len, filename.ptr, line, col);
    printf(fmt.ptr, );
}
*/
fn int main(char[][] argv) {
    char[][] other_names2 = enum_names(lexer::Token_type);
    char[][] lexer_status_names = enum_names(lexer::TokenizeStatus);
    for (usize i = 0; i < other_names2.len; i++) {
        printf("%i:%s\n", i, other_names2[i].ptr);
    }
   //char[][] names = enum_names(TestEnum);
   //char[][] other_names = enum_names(TestEnum2);
   /*
   for (usize i = 0; i < names.len; i++) {
     printf("%i:%s\n", i, names[i].ptr);
   }
   //should print:
   //0:BAR
   //1:BAZ
   //will fail here
   for (usize i = 0; i < other_names.len; i++) {
      printf("%i:%s\n", i, other_names[i].ptr);
   }
   //should print:
   //0:FOO
   //1:BARR
    */
    Source src;
    src.from_cstr(`
//a single line comment
/*  a  
    multiline
    commment
*/
    struct Value {
        int v;
        float f;
    }

    fn int some_func() {
        Value val;
        val.v = 42;
        val.f = 42.3;
        return val.v;
    }

    fn int main(char[][] argv) {
        return some_func();
    }`);
    /*
    char *s = src.entries;
    utf8_decode::print_utf8(s);
    */
    printf("%s\n", src.entries);

    TokenList tlist;
    TokenInfoList tilist;
    TokenDataList tdlist;

    lexer::TokenizeStatus r = lexer::tokenize_without_whitespace(&tlist, &tilist, &tdlist, &src);
    printf("Tokenized: %s\n", lexer_status_names[(usize)r].ptr);
    /*
    printf("Tokens: %i\n", (int)tlist.size);
    for (usize i = 0; i < tlist.size; i++) {
        usize val = (int)tlist.entries[i].tid;
        printf("%i:%i\n", i, val); //other_names2[].ptr
    }
    */
    char[][] char_id_names = enum_names(Char_id);
    char[][] token_type_names = enum_names(Token_type);

    for (usize i = 0; i < tlist.size; i++) {
        printf("rtkn[%i:%i](%i,%s): {%.*s}", (int)tilist.entries[i].line, (int)tilist.entries[i].col, (int)tlist.entries[i].tid, token_type_names[(int)tlist.entries[i].tid].ptr, tilist.entries[i].length, &src.entries[tilist.entries[i].offset]);
        if (tlist.entries[i].tid == Token_type.TKN_INTEGER) {
            printf("[%llu]", tdlist[i].first.u64);
        } else if (tlist.entries[i].tid == Token_type.TKN_FLOAT) {
            double d = (double)tdlist[i].first.u64 * math::pow(10.0, tdlist[i].second.i64);
            printf("[%llu, %lld, %f]", tdlist[i].first.u64, tdlist[i].second.i64, d);
        }
        printf("\n");
    }

   return 0;
}


//char[] x = $nameof(FooEnum.values[1]); // "BAR"
/*
fn int main(char[][] argv) 
{   

	int x = Foo.A.val;
	Foo f = Foo.B;
	Foo g = Foo.A;
	printf("%d (%s) %d (%s)\n", f.val, f.testme, g.val, g.testme);

    char[][] names = enum_names(lexer::Token_type); //lexer::TokenizeStatus.typeid.names;
    //enum_names(lexer::TokenizeStatus);
    for (usize i = 0; i < names.len; i++) {
        printf("%i:%s\n", i, names[i].ptr);
    }

    //printf("Tokenized: %s\n", zw[0]);

    
    Source src;
    src.from_cstr(`
    struct Value {
        int v;
    }

    fn int some_func() {
        Value val;
        val.v = 42;
        return val.v;
    }

    fn int main(char[][] argv) {
        return some_func();
    }`);

    printf("%s\n", src.entries);

    TokenList tlist;
    TokenInfoList tilist;
    TokenDataList tdlist;

    lexer::TokenizeStatus r = lexer::tokenize(&tlist, &tilist, &tdlist, &src);
    printf("Tokenized: %s\n", lexer::TokenizeStatus.values[(usize)r]);
    
    return 0;
}
*/