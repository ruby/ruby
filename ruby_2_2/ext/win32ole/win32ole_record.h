#ifndef WIN32OLE_RECORD_H
#define WIN32OLE_RECORD_H 1

VALUE cWIN32OLE_RECORD;
void ole_rec2variant(VALUE rec, VARIANT *var);
void olerecord_set_ivar(VALUE obj, IRecordInfo *pri, void *prec);
VALUE create_win32ole_record(IRecordInfo *pri, void *prec);
void Init_win32ole_record(void);

#endif
