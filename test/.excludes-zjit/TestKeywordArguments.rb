# See <https://github.com/Shopify/ruby/issues/970>.
# This tests fail with --zjit-disable-hir-opt
exclude(:test_required_keyword_with_newline, 'local assignment within eval')
