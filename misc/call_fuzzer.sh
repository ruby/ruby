# TODO: boost --num-iters to 1M+ for actual test

# Enable code GC so we don't stop compiling when we hit the code size limit
ruby --yjit-call-threshold=1 --yjit-code-gc misc/call_fuzzer.rb --num-iters=10000

# TODO:
# Do another pass with --verify-ctx
#ruby --yjit-call-threshold=1 --yjit-code-gc --yjit-verify-ctx misc/call_fuzzer.rb --num-iters=10000
