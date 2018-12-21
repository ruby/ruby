# https://app.wercker.com/ruby/ruby/runs/mjit-test2/5c18fd67c0c3d7001190a14d?step=5c18fda8cfa0fc0007fcc633
# https://app.wercker.com/ruby/ruby/runs/mjit-test2/5c1a3db51eea2b000777144a?step=5c1a3def78c72000078df9cf
# https://app.wercker.com/ruby/ruby/runs/mjit-test2/5c1b3a71c0c3d7001191f66e?step=5c1b5ed978c7200007961577
exclude(/./, 'most of tests are too fragile with --jit-wait and this remote fetcher cannot configure timeout')
