#!/usr/bin/env ruby

$KCODE = 'SJIS'

require 'soap/rpc/driver'
require 'IICD'; include IICD

server = 'http://www.iwebmethod.net/icd1.0/icd.asmx'
wiredump_dev = nil # STDERR

icd = SOAP::RPC::Driver.new(server, IICD::InterfaceNS)
icd.wiredump_dev = wiredump_dev
icd.default_encodingstyle = SOAP::EncodingStyle::ASPDotNetHandler::Namespace
IICD::add_method(icd)

puts "キーワード: 'microsoft'で見出し検索"
result = icd.SearchWord('microsoft', true)

id = nil
result.WORD.each do |word|
  puts "Title: " << word.title
  puts "Id: " << word.id
  puts "English: " << word.english
  puts "Japanese: " << word.japanese
  puts "----"
  id = word.id
end

item = icd.GetItemById(id)
puts
puts
puts "Title: " << item.word.title
puts "意味: " << item.meaning

#p icd.EnumWords

puts
puts
puts "キーワード: 'IBM'で全文検索"
icd.FullTextSearch("IBM").WORD.each do |word|
  puts "Title: " << word.title
  puts "Id: " << word.id
  puts "English: " << word.english
  puts "Japanese: " << word.japanese
  puts "----"
end
