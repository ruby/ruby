#!/usr/bin/env ruby
require 'openssl'

text = "abcdefghijklmnopqrstuvwxyz"
pass = "secret password"
salt = "8 octets"        # or nil
alg = "DES-EDE3-CBC"
#alg = "AES-128-CBC"

puts "--Setup--"
puts %(clear text:    "#{text}")
puts %(password:      "#{pass}")
puts %(salt:          "#{salt}")
puts %(cipher alg:    "#{alg}")
puts

puts "--Encrypting--"
des = OpenSSL::Cipher::Cipher.new(alg)
des.pkcs5_keyivgen(pass, salt)
des.encrypt
cipher =  des.update(text)
cipher << des.final
puts %(encrypted text: #{cipher.inspect})
puts

puts "--Decrypting--"
des = OpenSSL::Cipher::Cipher.new(alg)
des.pkcs5_keyivgen(pass, salt)
des.decrypt
out =  des.update(cipher)
out << des.final
puts %(decrypted text: "#{out}")
puts
