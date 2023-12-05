# TODO: we may want to test other call thresholds?
ruby --yjit-call-threshold=1 misc/call_fuzzer.rb

# TODO: we may also want to test with --verify-ctx?
# Could the call_fuzzer ruby script call itself with different options?
# May want to have a separate runner script