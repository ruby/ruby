# Stop at first error
set -e

# TODO
# TODO: boost --num-iters to 1M+ for actual test
# TODO
export NUM_ITERS=25000

# Enable code GC so we don't stop compiling when we hit the code size limit
ruby --yjit-call-threshold=1 --yjit-code-gc misc/call_fuzzer.rb --num-iters=$NUM_ITERS

# Do another pass with --verify-ctx
ruby --yjit-call-threshold=1 --yjit-code-gc --yjit-verify-ctx misc/call_fuzzer.rb --num-iters=$NUM_ITERS
