# Only happens when running with other tests
# Panics with:
#
#  thread '<unnamed>' panicked at zjit/src/asm/arm64/mod.rs:939:13:
#  Expected displacement -264 to be 9 bits or less
#
# May be related to https://github.com/Shopify/ruby/issues/646
exclude(/test_/, 'Tests make ZJIT panic')
