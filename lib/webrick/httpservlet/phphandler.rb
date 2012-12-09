#
# phphandler.rb -- PHPHandler Class
#
# This class is based on cgihandler.rb from the WEBrick bundle.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
# BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require 'rbconfig'
require 'tempfile'
require 'webrick/config'
require 'webrick/httpservlet/abstract'

module WEBrick
  module HTTPServlet

    class PHPHandler < AbstractServlet
      PHPCGI = 'php-cgi'

      def initialize(server, name)
        super(server, name)
        @phpcmd = File.join(@server[:PHPPath], PHPCGI).gsub("/", "\\")
        @php_fullpath_script = name
      end

      def do_GET(req, res)
        data = nil
        status = -1

        meta = req.meta_vars
        meta["SCRIPT_FILENAME"] = @php_fullpath_script
        meta["PATH"] = @config[:PHPPath]
        meta["REDIRECT_STATUS"] = "200" # php-cgi/apache specific value
        if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
          meta["SystemRoot"] = ENV["SystemRoot"]
        end
        ENV.update(meta)

        cgi_in = IO::popen(@phpcmd, "r+b")
        begin
          cgi_in.sync = true

          if req.body and req.body.bytesize > 0
            cgi_in.write(req.body)
          end
          cgi_in.close_write
        ensure
          data = cgi_in.read
          cgi_in.close_read
          status = $?.exitstatus
          sleep 0.1 if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
        end

        @script_filename = meta['SCRIPT_NAME']
        if status != 0
          @logger.error("PHPHandler: #{@script_filename} exit with #{status}")
        end

        data = "" unless data
        raw_header, body = data.split(/^[\xd\xa]+/, 2)
        raise HTTPStatus::InternalServerError,
              "PHPHandler: Premature end of script headers: #{@script_filename}" if body.nil?

        begin
          header = HTTPUtils::parse_header(raw_header)
          if /^(\d+)/ =~ header['status'][0]
            res.status = $1.to_i
            header.delete('status')
          end
          if header.has_key?('location')
            # RFC 3875 6.2.3, 6.2.4
            res.status = 302 unless (300...400) === res.status
          end
          if header.has_key?('set-cookie')
            header['set-cookie'].each { |k|
              res.cookies << Cookie.parse_set_cookie(k)
            }
            header.delete('set-cookie')
          end
          header.each { |key, val| res[key] = val.join(", ") }
        rescue => ex
          raise HTTPStatus::InternalServerError, ex.message
        end
        res.body = body
      end

      alias do_POST do_GET
    end

  end
end
