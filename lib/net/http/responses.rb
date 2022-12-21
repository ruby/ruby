# frozen_string_literal: true
#--
# https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml

module Net

  class HTTPUnknownResponse < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for informational (1xx) HTTP response classes.
  #
  # An informational response indicates that the request was received and understood.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.1xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#1xx_informational_response].
  #
  class HTTPInformation < HTTPResponse
    HAS_BODY = false
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for success (2xx) HTTP response classes.
  #
  # A success response indicates the action requested by the client
  # was received, understood, and accepted.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.2xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#2xx_success].
  #
  class HTTPSuccess < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPError                  #
  end

  # Parent class for redirection (3xx) HTTP response classes.
  #
  # A redirection response indicates the client must take additional action
  # to complete the request.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.3xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#3xx_redirection].
  #
  class HTTPRedirection < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPRetriableError         #
  end

  # Parent class for client error (4xx) HTTP response classes.
  #
  # A client error response indicates that the client may have caused an error.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.4xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#4xx_client_errors].
  #
  class HTTPClientError < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPClientException        #
  end

  # Parent class for server error (5xx) HTTP response classes.
  #
  # A server error response indicates that the server failed to fulfill a request.
  #
  # References:
  #
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#status.5xx].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#5xx_server_errors].
  #
  class HTTPServerError < HTTPResponse
    HAS_BODY = true
    EXCEPTION_TYPE = HTTPFatalError             #
  end

  # Response class for +Continue+ responses (status code 100).
  #
  # A +Continue+ response indicates that the server has received the request headers.
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/100].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-100-continue].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#100].
  #
  class HTTPContinue < HTTPInformation
    HAS_BODY = false
  end

  # Response class for <tt>Switching Protocol</tt> responses (status code 101).
  #
  # The <tt>Switching Protocol<tt> response indicates that the server has received
  # a request to switch protocols, and has agreed to do so.
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/101].
  # - {RFC 9110}[https://www.rfc-editor.org/rfc/rfc9110.html#name-101-switching-protocols].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#101].
  #
  class HTTPSwitchProtocol < HTTPInformation
    HAS_BODY = false
  end

  # Response class for +Processing+ responses (status code 102).
  #
  # The +Processing+ response indicates that the server has received
  # and is processing the request, but no response is available yet.
  #
  # References:
  #
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#102].
  #
  class HTTPProcessing < HTTPInformation
    HAS_BODY = false
  end

  # Response class for <tt>Early Hints</tt> responses (status code 103).
  #
  # The <tt>Early Hints</tt> indicates that the server has received
  # and is processing the request, and contains certain headers;
  # the final response is not available yet.
  #
  # References:
  #
  # - {Mozilla}[https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/103].
  # - {Wikipedia}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#103].
  #
  class HTTPEarlyHints < HTTPInformation
    HAS_BODY = false
  end

  # Response class for +OK+ responses (status code 200).
  #
  # The +OK+ response indicates that the server has received
  # a request and has responded successfully.
  # See {200 OK}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#200].
  class HTTPOK < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for +Created+ responses (status code 201).
  #
  # The +Created+ response indicates that the server has received
  # and has fulfilled a request to create a new resource.
  # See {201 Created}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#201].
  class HTTPCreated < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for +Accepted+ responses (status code 202).
  #
  # The +Accepted+ response indicates that the server has received
  # and is processing a request, but the processing has not yet been completed.
  # See {202 Accepted}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#202].
  class HTTPAccepted < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Non-Authoritative Information</tt> responses (status code 203).
  #
  # The <tt>Non-Authoritative Information</tt> response indicates that the server
  # is a transforming proxy (such as a Web accelerator)
  # that received a 200 OK response from its origin,
  # and is returning a modified version of the origin's response.
  # See {203 Non-Authoritative Information}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#203].
  class HTTPNonAuthoritativeInformation < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>No Content</tt> responses (status code 204).
  #
  # The <tt>No Content</tt> response indicates that the server
  # successfully processed the request, and is not returning any content.
  # See {204 No Content}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#204].
  class HTTPNoContent < HTTPSuccess
    HAS_BODY = false
  end

  # Response class for <tt>Reset Content</tt> responses (status code 205).
  #
  # The <tt>Reset Content</tt> response indicates that the server
  # successfully processed the request,
  # asks that the client reset its document view, and is not returning any content.
  # See {205 Reset Content}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#205].
  class HTTPResetContent < HTTPSuccess
    HAS_BODY = false
  end

  # Response class for <tt>Partial Content</tt> responses (status code 206).
  #
  # The <tt>Partial Content</tt> response indicates that the server is delivering
  # only part of the resource (byte serving)
  # due to a Range header in the request.
  # See {206 Partial Content}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#206].
  class HTTPPartialContent < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Multi-Status (WebDAV)</tt> responses (status code 207).
  #
  # The <tt>Multi-Status (WebDAV)</tt> response indicates that the server
  # has received the request,
  # and that the message body can contain a number of separate response codes.
  # See {207 Multi-Status (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#207].
  class HTTPMultiStatus < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Already Reported (WebDAV)</tt> responses (status code 208).
  #
  # The <tt>Already Reported (WebDAV)</tt> response indicates that the server
  # has received the request,
  # and that the members of a DAV binding have already been enumerated
  # in a preceding part of the (multi-status) response,
  # and are not being included again.
  # See {208 Already Reported (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#208].
  class HTTPAlreadyReported < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>IM Used</tt> responses (status code 226).
  #
  # The <tt>IM Used</tt> response indicates that the server has fulfilled a request
  # for the resource, and the response is a representation of the result
  # of one or more instance-manipulations applied to the current instance.
  # See {226 IM Used}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#226].
  class HTTPIMUsed < HTTPSuccess
    HAS_BODY = true
  end

  # Response class for <tt>Multiple Choices</tt> responses (status code 300).
  #
  # The <tt>Multiple Choices</tt> response indicates that the server
  # offers multiple options for the resource from which the client may choose.
  # See {300 Multiple Choices}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#300].
  class HTTPMultipleChoices < HTTPRedirection
    HAS_BODY = true
  end
  HTTPMultipleChoice = HTTPMultipleChoices

  # Response class for <tt>Moved Permanently</tt> responses (status code 301).
  #
  # The <tt>Moved Permanently</tt> response indicates that links or records
  # returning this response should be updated to use the given URL.
  # See {301 Moved Permanently}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#301].
  class HTTPMovedPermanently < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Found</tt> responses (status code 302).
  #
  # The <tt>Found</tt> response indicates that the client
  # should look at (browse to) another URL.
  # See {302 Found}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#302].
  class HTTPFound < HTTPRedirection
    HAS_BODY = true
  end
  HTTPMovedTemporarily = HTTPFound

  # Response class for <tt>See Other</tt> responses (status code 303).
  #
  # The response to the request can be found under another URI using the GET method.
  # See {303 See Other}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#303].
  class HTTPSeeOther < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Not Modified</tt> responses (status code 304).
  #
  # Indicates that the resource has not been modified since the version
  # specified by the request headers.
  # See {304 Not Modified}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#304].
  class HTTPNotModified < HTTPRedirection
    HAS_BODY = false
  end

  # Response class for <tt>Use Proxy</tt> responses (status code 305).
  #
  # The requested resource is available only through a proxy,
  # whose address is provided in the response.
  # See {305 Use Proxy}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#305].
  class HTTPUseProxy < HTTPRedirection
    HAS_BODY = false
  end

  # Response class for <tt>Temporary Redirect</tt> responses (status code 307).
  #
  # The request should be repeated with another URI;
  # however, future requests should still use the original URI.
  # See {307 Temporary Redirect}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#307].
  class HTTPTemporaryRedirect < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Permanent Redirect</tt> responses (status code 308).
  #
  # This and all future requests should be directed to the given URI.
  # See {308 Permanent Redirect}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#308].
  class HTTPPermanentRedirect < HTTPRedirection
    HAS_BODY = true
  end

  # Response class for <tt>Bad Request</tt> responses (status code 400).
  #
  # The server cannot or will not process the request due to an apparent client error.
  # See {400 Bad Request}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#400].
  class HTTPBadRequest < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unauthorized</tt> responses (status code 401).
  #
  # Authentication is required, but either was not provided or failed.
  # See {401 Unauthorized}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#401].
  class HTTPUnauthorized < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Payment Required</tt> responses (status code 402).
  #
  # Reserved for future use.
  # See {402 Payment Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#402].
  class HTTPPaymentRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Forbidden</tt> responses (status code 403).
  #
  # The request contained valid data and was understood by the server,
  # but the server is refusing action.
  # See {403 Forbidden}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#403].
  class HTTPForbidden < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Not Found</tt> responses (status code 404).
  #
  # The requested resource could not be found but may be available in the future.
  # See {404 Not Found}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#404].
  class HTTPNotFound < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Method Not Allowed</tt> responses (status code 405).
  #
  # The request method is not supported for the requested resource.
  # See {405 Method Not Allowed}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#405].
  class HTTPMethodNotAllowed < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Not Acceptable</tt> responses (status code 406).
  #
  # The requested resource is capable of generating only content
  # that not acceptable according to the Accept headers sent in the request.
  # See {406 Not Acceptable}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#406].
  class HTTPNotAcceptable < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Proxy Authentication Required</tt> responses (status code 407).
  #
  # The client must first authenticate itself with the proxy.
  # See {407 Proxy Authentication Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#407].
  class HTTPProxyAuthenticationRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Request Timeout</tt> responses (status code 408).
  #
  # The server timed out waiting for the request.
  # See {408 Request Timeout}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#408].
  class HTTPRequestTimeout < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestTimeOut = HTTPRequestTimeout

  # Response class for <tt>Conflict</tt> responses (status code 409).
  #
  # The request could not be processed because of conflict in the current state of the resource.
  # See {409 Conflict}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#409].
  class HTTPConflict < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Gone</tt> responses (status code 410).
  #
  # The resource requested was previously in use but is no longer available
  # and will not be available again.
  # See {410 Gone}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#410].
  class HTTPGone < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Length Required</tt> responses (status code 411).
  #
  # The request did not specify the length of its content,
  # which is required by the requested resource.
  # See {411 Length Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#411].
  class HTTPLengthRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Precondition Failed</tt> responses (status code 412).
  #
  # The server does not meet one of the preconditions
  # specified in the request headers.
  # See {412 Precondition Failed}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#412].
  class HTTPPreconditionFailed < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Payload Too Large</tt> responses (status code 413).
  #
  # The request is larger than the server is willing or able to process.
  # See {413 Payload Too Large}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#413].
  class HTTPPayloadTooLarge < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestEntityTooLarge = HTTPPayloadTooLarge

  # Response class for <tt>URI Too Long</tt> responses (status code 414).
  #
  # The URI provided was too long for the server to process.
  # See {414 URI Too Long}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#414].
  class HTTPURITooLong < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestURITooLong = HTTPURITooLong
  HTTPRequestURITooLarge = HTTPRequestURITooLong

  # Response class for <tt>Unsupported Media Type</tt> responses (status code 415).
  #
  # The request entity has a media type which the server or resource does not support.
  # See {415 Unsupported Media Type}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#415].
  class HTTPUnsupportedMediaType < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Range Not Satisfiable</tt> responses (status code 416).
  #
  # The request entity has a media type which the server or resource does not support.
  # See {416 Range Not Satisfiable}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#416].
  class HTTPRangeNotSatisfiable < HTTPClientError
    HAS_BODY = true
  end
  HTTPRequestedRangeNotSatisfiable = HTTPRangeNotSatisfiable

  # Response class for <tt>Expectation Failed</tt> responses (status code 417).
  #
  # The server cannot meet the requirements of the Expect request-header field.
  # See {417 Expectation Failed}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#417].
  class HTTPExpectationFailed < HTTPClientError
    HAS_BODY = true
  end

  # 418 I'm a teapot - RFC 2324; a joke RFC
  # See https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#418.

  # 420 Enhance Your Calm - Twitter

  # Response class for <tt>Misdirected Request</tt> responses (status code 421).
  #
  # The request was directed at a server that is not able to produce a response.
  # See {421 Misdirected Request}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#421].
  class HTTPMisdirectedRequest < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unprocessable Entity</tt> responses (status code 422).
  #
  # The request was well-formed but had semantic errors.
  # See {422 Unprocessable Entity}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#422].
  class HTTPUnprocessableEntity < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Locked (WebDAV)</tt> responses (status code 423).
  #
  # The requested resource is locked.
  # See {423 Locked (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#423].
  class HTTPLocked < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Failed Dependency (WebDAV)</tt> responses (status code 424).
  #
  # The request failed because it depended on another request and that request failed.
  # See {424 Failed Dependency (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#424].
  class HTTPFailedDependency < HTTPClientError
    HAS_BODY = true
  end

  # 425 Too Early
  # https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#425.

  # Response class for <tt>Upgrade Required</tt> responses (status code 426).
  #
  # The client should switch to the protocol given in the Upgrade header field.
  # See {426 Upgrade Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#426].
  class HTTPUpgradeRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Precondition Required</tt> responses (status code 428).
  #
  # The origin server requires the request to be conditional.
  # See {428 Precondition Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#428].
  class HTTPPreconditionRequired < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Too Many Requests</tt> responses (status code 429).
  #
  # The user has sent too many requests in a given amount of time.
  # See {429 Too Many Requests}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#429].
  class HTTPTooManyRequests < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Request Header Fields Too Large</tt> responses (status code 431).
  #
  # An individual header field is too large,
  # or all the header fields collectively, are too large.
  # See {431 Request Header Fields Too Large}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#431].
  class HTTPRequestHeaderFieldsTooLarge < HTTPClientError
    HAS_BODY = true
  end

  # Response class for <tt>Unavailable For Legal Reasons</tt> responses (status code 451).
  #
  # A server operator has received a legal demand to deny access to a resource or to a set of resources
  # that includes the requested resource.
  # See {451 Unavailable For Legal Reasons}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#451].
  class HTTPUnavailableForLegalReasons < HTTPClientError
    HAS_BODY = true
  end
  # 444 No Response - Nginx
  # 449 Retry With - Microsoft
  # 450 Blocked by Windows Parental Controls - Microsoft
  # 499 Client Closed Request - Nginx

  # Response class for <tt>Internal Server Error</tt> responses (status code 500).
  #
  # An unexpected condition was encountered and no more specific message is suitable.
  # See {500 Internal Server Error}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#500].
  class HTTPInternalServerError < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Not Implemented</tt> responses (status code 501).
  #
  # The server either does not recognize the request method,
  # or it lacks the ability to fulfil the request.
  # See {501 Not Implemented}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#501].
  class HTTPNotImplemented < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Bad Gateway</tt> responses (status code 502).
  #
  # The server was acting as a gateway or proxy
  # and received an invalid response from the upstream server.
  # See {502 Bad Gateway}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#502].
  class HTTPBadGateway < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Service Unavailable</tt> responses (status code 503).
  #
  # The server cannot handle the request
  # (because it is overloaded or down for maintenance).
  # See {503 Service Unavailable}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#503].
  class HTTPServiceUnavailable < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Gateway Timeout</tt> responses (status code 504).
  #
  # The server was acting as a gateway or proxy
  # and did not receive a timely response from the upstream server.
  # See {504 Gateway Timeout}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#504].
  class HTTPGatewayTimeout < HTTPServerError
    HAS_BODY = true
  end
  HTTPGatewayTimeOut = HTTPGatewayTimeout

  # Response class for <tt>HTTP Version Not Supported</tt> responses (status code 505).
  #
  # The server does not support the HTTP version used in the request.
  # See {505 HTTP Version Not Supported}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#505].
  class HTTPVersionNotSupported < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Variant Also Negotiates</tt> responses (status code 506).
  #
  # Transparent content negotiation for the request results in a circular reference.
  # See {506 Variant Also Negotiates}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#506].
  class HTTPVariantAlsoNegotiates < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Insufficient Storage (WebDAV)</tt> responses (status code 507).
  #
  # The server is unable to store the representation needed to complete the request.
  # See {507 Insufficient Storage (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#507].
  class HTTPInsufficientStorage < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Loop Detected (WebDAV)</tt> responses (status code 508).
  #
  # The server detected an infinite loop while processing the request.
  # See {508 Loop Detected (WebDAV)}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#508].
  class HTTPLoopDetected < HTTPServerError
    HAS_BODY = true
  end
  # 509 Bandwidth Limit Exceeded - Apache bw/limited extension

  # Response class for <tt>Not Extended</tt> responses (status code 510).
  #
  # Further extensions to the request are required for the server to fulfill it.
  # See {510 Not Extended}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#510].
  class HTTPNotExtended < HTTPServerError
    HAS_BODY = true
  end

  # Response class for <tt>Network Authentication Required</tt> responses (status code 511).
  #
  # The client needs to authenticate to gain network access.
  # See {511 Network Authentication Required}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes#511].
  class HTTPNetworkAuthenticationRequired < HTTPServerError
    HAS_BODY = true
  end

end

class Net::HTTPResponse
  CODE_CLASS_TO_OBJ = {
    '1' => Net::HTTPInformation,
    '2' => Net::HTTPSuccess,
    '3' => Net::HTTPRedirection,
    '4' => Net::HTTPClientError,
    '5' => Net::HTTPServerError
  }
  CODE_TO_OBJ = {
    '100' => Net::HTTPContinue,
    '101' => Net::HTTPSwitchProtocol,
    '102' => Net::HTTPProcessing,
    '103' => Net::HTTPEarlyHints,

    '200' => Net::HTTPOK,
    '201' => Net::HTTPCreated,
    '202' => Net::HTTPAccepted,
    '203' => Net::HTTPNonAuthoritativeInformation,
    '204' => Net::HTTPNoContent,
    '205' => Net::HTTPResetContent,
    '206' => Net::HTTPPartialContent,
    '207' => Net::HTTPMultiStatus,
    '208' => Net::HTTPAlreadyReported,
    '226' => Net::HTTPIMUsed,

    '300' => Net::HTTPMultipleChoices,
    '301' => Net::HTTPMovedPermanently,
    '302' => Net::HTTPFound,
    '303' => Net::HTTPSeeOther,
    '304' => Net::HTTPNotModified,
    '305' => Net::HTTPUseProxy,
    '307' => Net::HTTPTemporaryRedirect,
    '308' => Net::HTTPPermanentRedirect,

    '400' => Net::HTTPBadRequest,
    '401' => Net::HTTPUnauthorized,
    '402' => Net::HTTPPaymentRequired,
    '403' => Net::HTTPForbidden,
    '404' => Net::HTTPNotFound,
    '405' => Net::HTTPMethodNotAllowed,
    '406' => Net::HTTPNotAcceptable,
    '407' => Net::HTTPProxyAuthenticationRequired,
    '408' => Net::HTTPRequestTimeout,
    '409' => Net::HTTPConflict,
    '410' => Net::HTTPGone,
    '411' => Net::HTTPLengthRequired,
    '412' => Net::HTTPPreconditionFailed,
    '413' => Net::HTTPPayloadTooLarge,
    '414' => Net::HTTPURITooLong,
    '415' => Net::HTTPUnsupportedMediaType,
    '416' => Net::HTTPRangeNotSatisfiable,
    '417' => Net::HTTPExpectationFailed,
    '421' => Net::HTTPMisdirectedRequest,
    '422' => Net::HTTPUnprocessableEntity,
    '423' => Net::HTTPLocked,
    '424' => Net::HTTPFailedDependency,
    '426' => Net::HTTPUpgradeRequired,
    '428' => Net::HTTPPreconditionRequired,
    '429' => Net::HTTPTooManyRequests,
    '431' => Net::HTTPRequestHeaderFieldsTooLarge,
    '451' => Net::HTTPUnavailableForLegalReasons,

    '500' => Net::HTTPInternalServerError,
    '501' => Net::HTTPNotImplemented,
    '502' => Net::HTTPBadGateway,
    '503' => Net::HTTPServiceUnavailable,
    '504' => Net::HTTPGatewayTimeout,
    '505' => Net::HTTPVersionNotSupported,
    '506' => Net::HTTPVariantAlsoNegotiates,
    '507' => Net::HTTPInsufficientStorage,
    '508' => Net::HTTPLoopDetected,
    '510' => Net::HTTPNotExtended,
    '511' => Net::HTTPNetworkAuthenticationRequired,
  }
end
