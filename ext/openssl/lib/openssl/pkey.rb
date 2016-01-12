# frozen_string_literal: false
module OpenSSL
  module PKey
    if defined?(OpenSSL::PKey::DH)

    class DH
      DEFAULT_1024 = new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAJ0lOVy0VIr/JebWn0zDwY2h+rqITFOpdNr6ugsgvkDXuucdcChhYExJ
AV/ZD2AWPbrTqV76mGRgJg4EddgT1zG0jq3rnFdMj2XzkBYx3BVvfR0Arnby0RHR
T4h7KZ/2zmjvV+eF8kBUHBJAojUlzxKj4QeO2x20FP9X5xmNUXeDAgEC
-----END DH PARAMETERS-----
      _end_of_pem_
    end

    DEFAULT_TMP_DH_CALLBACK = lambda { |ctx, is_export, keylen|
      warn "using default DH parameters." if $VERBOSE
      case keylen
      when 1024 then OpenSSL::PKey::DH::DEFAULT_1024
      else
        nil
      end
    }

    else
      DEFAULT_TMP_DH_CALLBACK = nil
    end
  end
end
