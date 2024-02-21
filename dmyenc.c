// This file is used by dynamically-linked ruby, which has no
// statically-linked encodings other than the builtin encodings.
//
// - miniruby does not use this Init_enc. Instead, "miniinit.c"
//   provides Init_enc, which defines only the builtin encodings.
//
// - Dynamically-linked ruby uses this Init_enc, which requires
//   "enc/encdb.so" to load the builtin encodings and set up the
//   optional encodings.
//
// - Statically-linked ruby does not use this Init_enc. Instead,
//   "enc/encinit.c" (which is a generated file) defines Init_enc,
//   which activates the encodings.

#define require(name) ruby_require_internal(name, (unsigned int)sizeof(name)-1)
int ruby_require_internal(const char *, int);

void
Init_enc(void)
{
    if (require("enc/encdb.so") == 1) {
        require("enc/trans/transdb.so");
    }
}
