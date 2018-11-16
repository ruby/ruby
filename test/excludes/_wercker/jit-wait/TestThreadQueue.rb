# https://app.wercker.com/ruby/ruby/runs/test-mjit-wait/5bcfd19aa9806e000655c598?step=5bcfd1d5acc4510006e00f77
exclude(:test_queue_with_trap, 'this test randomly fails with --jit-wait')
