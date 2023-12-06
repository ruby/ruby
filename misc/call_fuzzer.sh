# TODO: boost --num-iters to 1M+ for actual test

# Enable code GC so we don't stop compiling when we hit the code size limit
ruby --yjit-call-threshold=1 --yjit-code-gc misc/call_fuzzer.rb --num-iters=10000

# TODO: we may also want to do another pass with --verify-ctx?
