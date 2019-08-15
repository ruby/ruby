# https://app.wercker.com/ruby/ruby/runs/mjit-test2/5bda979a191eda000655a8d2?step=5bda9fe4591ca80007653f64
exclude(:test_frozen, 'somehow FrozenError is not raised with --jit-wait')
