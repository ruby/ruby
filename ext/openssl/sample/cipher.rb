#!/usr/bin/env ruby
require 'openssl'

text = "abcdefghijklmnopqrstuvwxyz"
key = "key"
alg = "DES-EDE3-CBC"
#alg = "AES-128-CBC"

puts "--Setup--"
puts %(clear text:    "#{text}")
puts %(symmetric key: "#{key}")
puts %(cipher alg:    "#{alg}")
puts

puts "--Encrypting--"
des = OpenSSL::Cipher::Cipher.new(alg)
des.encrypt(key) #, "iv12345678")
cipher =  des.update(text)
cipher << des.final
puts %(encrypted text: #{cipher.inspect})
puts

puts "--Decrypting--"
des = OpenSSL::Cipher::Cipher.new(alg)
des.decrypt(key) #, "iv12345678")
out =  des.update(cipher)
out << des.final
puts %(decrypted text: "#{out}")
puts
