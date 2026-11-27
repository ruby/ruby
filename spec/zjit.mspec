# Fails with --zjit-disable-hir-opt. See https://github.com/Shopify/ruby/issues/970
MSpec.register(:exclude, "Kernel#eval updates a local in a scope above a surrounding block scope")
