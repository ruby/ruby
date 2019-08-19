/ANSI-C code/{
  h
  s/.*/ANSI:offset:/
  x
}
/\/\*!ANSI{\*\//{
  G
  s/\/\*!ANSI{\*\/\(.*\)\/\*}!ANSI\*\/\(.*\)\nANSI:.*/\/\*\1\*\/\2/
}
s/(int)([a-z_]*)&((struct \([a-zA-Z_0-9][a-zA-Z_0-9]*\)_t *\*)0)->\1_str\([1-9][0-9]*\),/gperf_offsetof(\1, \2),/g
/^#line/{
  G
  x
  s/:offset:/:/
  x
  s/\(.*\)\(\n\).*:offset:.*/#define gperf_offsetof(s, n) (short)offsetof(struct s##_t, s##_str##n)\2\1/
  s/\n[^#].*//
}
/^[a-zA-Z_0-9]*hash/,/^}/{
  s/ hval = / hval = (unsigned int)/
  s/ return / return (unsigned int)/
}
