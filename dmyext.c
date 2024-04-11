// This file is used by dynamically-linked ruby, which has no
// statically-linked extension libraries.
//
// - miniruby does not use this Init_ext. Instead, "miniinit.c"
//   provides Init_enc, which does nothing too. It does not support
//   require'ing extension libraries.
//
// - Dynamically-linked ruby uses this Init_ext, which does
//   nothing. It loads extension libraries by dlopen, etc.
//
// - Statically-linked ruby does not use this Init_ext. Instead,
//   "ext/extinit.c" (which is a generated file) defines Init_ext,
//   which activates the (statically-linked) extension libraries.

void
Init_ext(void)
{
}
