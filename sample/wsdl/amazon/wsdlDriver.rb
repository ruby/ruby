require 'soap/wsdlDriver'

book = ARGV.shift || "Ruby"

# AmazonSearch.rb is generated from WSDL.
# Run "wsdl2ruby.rb --wsdl http://soap.amazon.com/schemas2/AmazonWebServices.wsdl --classDef --force"
require 'AmazonSearch.rb'

=begin
Or, define the class by yourself like this.

class KeywordRequest
  def initialize(keyword = nil,
      page = nil,
      mode = nil,
      tag = nil,
      type = nil,
      devtag = nil,
      sort = nil)
    @keyword = keyword
    @page = page
    @mode = mode
    @tag = tag
    @type = type
    @devtag = devtag
    @sort = sort
  end
end
=end

# You must get 'developer's token" from http://associates.amazon.com/exec/panama/associates/ntg/browse/-/1067662 to use Amazon Web Services 2.0.
#devtag = File.open(File.expand_path("~/.amazon_key")).read.chomp

AMAZON_WSDL = 'http://soap.amazon.com/schemas2/AmazonWebServices.wsdl'
amazon = SOAP::WSDLDriverFactory.new(AMAZON_WSDL).create_driver
p "WSDL loaded"
amazon.generate_explicit_type = true
#amazon.wiredump_dev = STDERR

# Show sales rank.
req = KeywordRequest.new(book, "1", "books", "webservices-20", "lite", devtag, "+salesrank")
amazon.KeywordSearchRequest(req).Details.each do |detail|
  puts "== #{detail.ProductName}"
  puts "Author: #{detail.Authors.join(", ")}"
  puts "Release date: #{detail.ReleaseDate}"
  puts "List price: #{detail.ListPrice}, our price: #{detail.OurPrice}"
  puts
end
