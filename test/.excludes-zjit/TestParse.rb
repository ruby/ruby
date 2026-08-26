# See <https://github.com/Shopify/ruby/issues/970>.
# These tests fail with --zjit-disable-hir-opt
exclude(:test_utf8_bom, 'local assignment within eval')
exclude(:test_pow_asgn, 'local assignment within eval')
exclude(:test_backquote, 'local assignment within eval')
exclude(:test_dot_in_next_line, 'local assignment within eval')
exclude(:test_here_document, 'local assignment within eval')
exclude(:test_magic_comment, 'local assignment within eval')
