# See <https://github.com/Shopify/ruby/issues/970>.
# This tests fail with --zjit-disable-hir-opt
exclude(:test_unknown_string_option, 'local assignment within eval')
