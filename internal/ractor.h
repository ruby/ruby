#ifndef INTERNAL_RACTOR_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RACTOR_H

void rb_ractor_ensure_main_ractor(const char *msg);
uint32_t rb_ractor_last_id(void);

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_RACTOR_H */
