module utf8_decode;
//see: https://bjoern.hoehrmann.de/utf-8/decoder/dfa/

const uint UTF8_ACCEPT = 0;
const uint UTF8_REJECT = 1;

const char[] UTF8D = {
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
  8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
  0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
  0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
  0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1, // s0..s0
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1, // s1..s2
  1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1, // s3..s4
  1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1, // s5..s6
  1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // s7..s8
};

extern fn void printf(char*, ...);

fn uint decode(uint* state, uint* codep, uint byte) @inline {
  uint ty = UTF8D[byte];

  *codep = (*state != UTF8_ACCEPT) ?
    (byte & 0x3fu) | (*codep << 6) :
    (0xff >> ty) & (byte);

  *state = UTF8D[256 + *state*16 + ty];
  return *state;
}

fn int is_utf8(char* s) @inline {
  uint codepoint = 0;
  uint state = 0;

  while (*s) {
    decode(&state, &codepoint, *s++);
  }

  return (int)(state == UTF8_ACCEPT);
}

fn uint print_utf8(char *s) {
    uint state = 0;
    uint codepoint = 0;
    uint prev = 0;
    for (; *s; ++s) {
        uint t = utf8_decode::decode(&state, &codepoint, *s);
        if (t == utf8_decode::UTF8_ACCEPT) {
            printf("U+%04X\n", codepoint);
        } else if (t == utf8_decode::UTF8_REJECT) {
            printf("U+%04X\n", 0x0000fffd);
            state = UTF8_ACCEPT;
            if (prev != UTF8_ACCEPT) {
                s--;
            }
        }
        prev = state;
    }

    return state;
}