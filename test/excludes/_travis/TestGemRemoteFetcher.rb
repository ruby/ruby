# https://travis-ci.org/ruby/ruby/jobs/444240249
# raises: OpenSSL::SSL::SSLError "SSL_read: tlsv1 alert decrypt error"
exclude(:test_do_not_allow_invalid_client_cert_auth_connection,
        'This test is failing with OpenSSL 1.1.1 on Travis osx build')
