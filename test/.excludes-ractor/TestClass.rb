exclude(:test_s_inherited, "class variables")
exclude(:test_singleton_class_should_has_own_namespace, "global variables")
exclude(:test_nonascii_name, "global side effects")
exclude(:test_check_inheritable_break_with_object, "global side effects")
exclude(/^test_subclass_gc/, "Takes long time")
# 'block in TestClass#test_subclasses'
exclude(:test_subclasses, "RuntimeError: defined with an un-shareable Proc in a different Ractor")
