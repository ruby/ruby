#include <psych.h>

VALUE cPsychVisitorsYamlTree;

void Init_psych_yaml_tree(void)
{
    VALUE psych     = rb_define_module("Psych");
    VALUE visitors  = rb_define_module_under(psych, "Visitors");
    VALUE visitor   = rb_define_class_under(visitors, "Visitor", rb_cObject);
    cPsychVisitorsYamlTree = rb_define_class_under(visitors, "YAMLTree", visitor);
}
