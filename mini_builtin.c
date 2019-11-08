#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

// include from miniinits.c

static const char *
read_file(const char *fname, size_t *psize)
{
    struct stat st;
    char *code;
    FILE *fp;

    if (stat(fname, &st) != 0) {
        rb_bug("stat fails: %s", fname);
    }

    size_t fsize = st.st_size;
    if ((code = malloc(fsize + 1)) == NULL) {
        rb_bug("can't allocate memory: %s (%d)", fname, (int)fsize);
    }

    if ((fp = fopen(fname, "rb")) == NULL) {
        rb_bug("can't open file: %s", fname);
    }

    size_t read_size = fread(code, 1, fsize, fp);
    if (read_size != fsize) {
        rb_bug("can't read file enough: %s (expect %d but was %d)", fname, (int)fsize, (int)read_size);
    }

    code[fsize] = 0;
    *psize = fsize;
    return code;
}

static struct st_table *loaded_builtin_table;
static char srcdir[0x200];
static const char fname[] = "mini_builtin.c";

static const char *
feature_path(const char *name)
{
    static char path[0x200];
    snprintf(path, 0x200-1, "%s%s.rb", srcdir, name);
    // fprintf(stderr, "srcdir:%s, path:%s, PATH_SEP_CHAR:%c\n", srcdir, path, PATH_SEP_CHAR);
    return path;
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    size_t fsize;
    const char *code = read_file(feature_path(feature_name), &fsize);
    VALUE code_str = rb_utf8_str_new_static(code, fsize);
    VALUE name_str = rb_sprintf("<internal:%s>", feature_name);
    rb_obj_hide(code_str);

    rb_ast_t *ast = rb_parser_compile_string_path(rb_parser_new(), name_str, code_str, 1);

    GET_VM()->builtin_function_table = table;
    const rb_iseq_t *iseq = rb_iseq_new(&ast->body, name_str, name_str, Qnil, NULL, ISEQ_TYPE_TOP);
    GET_VM()->builtin_function_table = NULL;

    rb_ast_dispose(ast);
    free((void *)code); // code_str becomes broken.

    // register (loaded iseq will not be freed)
    st_insert(loaded_builtin_table, (st_data_t)feature_name, (st_data_t)iseq);
    rb_gc_register_mark_object((VALUE)iseq);

    // eval
    rb_iseq_eval(iseq);
}

static int
each_builtin_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    const char *feature = (const char *)key;
    const rb_iseq_t *iseq = (const rb_iseq_t *)val;

    rb_yield_values(2, rb_str_new2(feature), rb_iseqw_new(iseq));

    return ST_CONTINUE;
}

static VALUE
each_builtin(VALUE self)
{
    st_foreach(loaded_builtin_table, each_builtin_i, 0);
    return Qnil;
}

void
Init_builtin(void)
{
    rb_define_singleton_method(rb_cRubyVM, "each_builtin", each_builtin, 0);
    loaded_builtin_table = st_init_strtable();

    // check srcdir
    // assume __FILE__ encoding is ASCII compatible.
    int pos = strlen(__FILE__) - strlen(fname);
    if (pos < 0) rb_bug("strlen(%s) - strlen(%s) < 0", __FILE__, fname);

    if (strcmp(__FILE__ + pos, fname) != 0) {
        rb_bug("%s does not terminate with %s\n", __FILE__, fname);
    }
    strncpy(srcdir, __FILE__, 0x200-1);
    srcdir[pos] = 0;
}
