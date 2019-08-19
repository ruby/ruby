# These tests randomly hang forever. For testing other things properly, skipped for now.

# https://travis-ci.org/ruby/ruby/jobs/566409880
exclude(:test_execopts_redirect_open_fifo_interrupt_raise, 'This test randomly hangs on Travis osx')

# https://travis-ci.org/ruby/ruby/jobs/567547060
exclude(:test_execopts_redirect_open_fifo_interrupt_print, 'This test randomly hangs on Travis osx')
