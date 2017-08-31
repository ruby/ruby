# frozen_string_literal: false
module OpenSSL
  module PKey
    if defined?(OpenSSL::PKey::DH)

    class DH
      # :nodoc:
      DEFAULT_1024 = new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIGHAoGBAJ0lOVy0VIr/JebWn0zDwY2h+rqITFOpdNr6ugsgvkDXuucdcChhYExJ
AV/ZD2AWPbrTqV76mGRgJg4EddgT1zG0jq3rnFdMj2XzkBYx3BVvfR0Arnby0RHR
T4h7KZ/2zmjvV+eF8kBUHBJAojUlzxKj4QeO2x20FP9X5xmNUXeDAgEC
-----END DH PARAMETERS-----
      _end_of_pem_

      # :nodoc:
      DEFAULT_2048 = new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA7E6kBrYiyvmKAMzQ7i8WvwVk9Y/+f8S7sCTN712KkK3cqd1jhJDY
JbrYeNV3kUIKhPxWHhObHKpD1R84UpL+s2b55+iMd6GmL7OYmNIT/FccKhTcveab
VBmZT86BZKYyf45hUF9FOuUM9xPzuK3Vd8oJQvfYMCd7LPC0taAEljQLR4Edf8E6
YoaOffgTf5qxiwkjnlVZQc3whgnEt9FpVMvQ9eknyeGB5KHfayAc3+hUAvI3/Cr3
1bNveX5wInh5GDx1FGhKBZ+s1H+aedudCm7sCgRwv8lKWYGiHzObSma8A86KG+MD
7Lo5JquQ3DlBodj3IDyPrxIv96lvRPFtAwIBAg==
-----END DH PARAMETERS-----
      _end_of_pem_
    end

    # :nodoc:
    DEFAULT_TMP_DH_CALLBACK = lambda { |ctx, is_export, keylen|
      warn "using default DH parameters." if $VERBOSE
      case keylen
      when 1024 then OpenSSL::PKey::DH::DEFAULT_1024
      when 2048 then OpenSSL::PKey::DH::DEFAULT_2048
      else
        nil
      end
    }

    else
      DEFAULT_TMP_DH_CALLBACK = nil
    end
  end
end
