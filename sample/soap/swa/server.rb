require 'soap/rpc/standaloneServer'
require 'soap/attachment'

class SwAService
  def get_file
    return {
      'name' => $0,
      'file' => SOAP::Attachment.new(File.open($0))
    }
  end

  def put_file(name, file)
    "File '#{name}' was received ok."
  end
end

server = SOAP::RPC::StandaloneServer.new('SwAServer',
  'http://www.acmetron.com/soap', '0.0.0.0', 7000)
server.add_servant(SwAService.new)
trap(:INT) do
  server.shutdown
end
server.start
