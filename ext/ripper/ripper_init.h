#ifndef RIPPER_INIT_H
#define RIPPER_INIT_H

extern VALUE rb_ripper_none;
VALUE ripper_get_value(VALUE v);
ID ripper_get_id(VALUE v);
PRINTF_ARGS(void ripper_compile_error(struct parser_params*, const char *fmt, ...), 2, 3);

#endif /* RIPPER_INIT_H */
