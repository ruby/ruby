# https://travis-ci.org/ruby/ruby/jobs/444232675
# randomly raises: Errno::EPROTOTYPE "Protocol wrong type for socket"
exclude(:test_imaps_post_connection_check, 'This test randomly fails with OpenSSL 1.1.1 on Travis osx build')
