require 'digest/sha1'


module OpenProfile
  
  JSON_BASE = {'namespace' => 'openprofile-0.1'}
  
  def self.random_alphanumeric(length = 32)
    characters = ('a'..'z').to_a + ('A'..'Z').to_a
    (0...length).collect { characters[Kernel.rand(characters.length)] }.join
  end
  
  def self.sha1(string)
    Digest::SHA1.hexdigest string
  end
  
  
  
  def self.respond_signed(headers, body)
    secret = headers.delete :secret
    header = headers.keys.sort.collect {|k| k.to_s+'='+headers[k].to_s }.join(',')
    
    unless body.is_a? String
      body = MultiJson.encode(body)
    end
    
    document = header+':'+body
    
    signature = OpenProfile.sha1(secret+':'+document)
    signed_document = signature+':'+document
    
    return signed_document
  end
  def self.respond(body)
    unless body.is_a? String
      body = MultiJson.encode(body)
    end
    return body
  end
  
  def self.parse_signed_document(signed_document, block)
    signature, header_string, document = signed_document.split(':', 3)
    
    body = MultiJson.decode(document)
    headers = {}
    
    header_string.split(',').each do |pair|
      parts = pair.split('=', 2)
      headers[parts.first.to_sym] = parts.last
    end
    
    opts = block.call(headers[:key])
    
    d = Document.new
    d.signature = signature
    d.headers = headers.dup
    d.body = body.dup
    
    if opts
      test_signature = OpenProfile.sha1(opts[:secret]+':'+header_string+':'+document)
      d.valid_signature = (test_signature == signature)
    end
    
    return d
  end
  
  def self.parse_handshake_signed_document(signed_document)
    signature, header_string, document = signed_document.split(':', 3)
    
    body = MultiJson.decode(document)
    headers = {}
    
    header_string.split(',').each do |pair|
      parts = pair.split('=', 2)
      headers[parts.first.to_sym] = parts.last
    end
    
    test_signature = OpenProfile.sha1(body['secret']+':'+header_string+':'+document)
    
    d = Document.new
    d.signature = signature
    d.valid_signature = (test_signature == signature)
    d.headers = headers.dup
    d.body = body.dup
    
    return d
  end
  
  class Document
    attr_accessor :signature
    attr_accessor :headers
    attr_accessor :body
    attr_accessor :valid_signature
    attr_accessor :error_response
    
    def initialize(opts = {})
      @signature = false or opts[:signature]
      @headers = (opts[:headers] or {})
      @body = (opts[:body] or {})
      @valid_signature = false or opts[:valid_signature]
      @error_response = false or opts[:error_response]
    end
    
    def valid?
      @valid_signature and !@error_response
    end
    
    def self.headers(string)
      signature, header_string, document = string.split(':', 3)
      headers = {}
      header_string.split(',').each do |pair|
        parts = pair.split('=', 2)
        headers[parts.first.to_sym] = parts.last
      end
      return headers.dup
    end
    
    def self.decode(string, opts = {})
      secret = opts[:secret]
      
      if string[0].chr == '{'
        document = string
        signed = false
      else
        signature, header_string, document = string.split(':', 3)
        signed = true
      end
      
      begin
        body = MultiJson.decode(document)
      rescue
        puts $!; puts $@
        return Document.new(:body => {'status' => 'failure', 'message' => 'Error parsing document'}, :error_response => true)
      end
      unless signed
        return Document.new({
          :body => body.dup,
          :signature => false,
          :valid_signature => false
        })
      end
      
      headers = {}
      header_string.split(',').each do |pair|
        parts = pair.split('=', 2)
        headers[parts.first.to_sym] = parts.last
      end
      
      unless secret
        secret = body['secret']
      end
      
      test_signature = OpenProfile.sha1(secret+':'+header_string+':'+document)
      
      return Document.new({
        :body => body.dup,
        :signature => signature,
        :headers => headers.dup,
        :valid_signature => (test_signature == signature)
      })
    end
    
    
    
    def encode
      body = (@body.is_a? String) ? @body : MultiJson.encode(@body)
      
      headers = @headers.dup
      
      secret = headers.delete :secret
      return body unless secret
      
      headers = headers.keys.map {|k| k.to_s+'='+headers[k].to_s }.join(',')
      document = headers+':'+body
      signature = OpenProfile.sha1(secret+':'+document)
      
      return signature+':'+document
    end
  end
  
  class Request
    
    #def self.post(url, header, body)
    #  
    #  puts header.class.inspect
    #  
    #end
    
    def self.post_signed(url, headers, body)
      header = 'key='+headers[:key]
      
      unless body.is_a? String
        body = MultiJson.encode(body)
      end
      
      document = header+':'+body
      
      signature = OpenProfile.sha1(headers[:secret]+':'+document)
      signed_document = signature+':'+document
      
      return parse_response({:secret => headers[:secret]}, HTTParty.post(url, {:body => signed_document}))
    end
    
    def self.parse_response(opts, response)
      secret = opts[:secret]
      signed_document = (response.body).strip
      
      d = Document.new
      
      if signed_document.length == 0 or signed_document[0].chr == '{'
        d.error_response = true
        d.body = MultiJson.decode(signed_document)
        return d
      end
      
      signature, header_string, document = signed_document.split(':', 3)
      
      body = MultiJson.decode(document)
      headers = {}
      header_string.split(',').each do |pair|
        parts = pair.split('=', 2)
        headers[parts.first.to_sym] = parts.last
      end
      
      d.signature = signature
      d.headers = headers.dup
      d.body = body.dup
      test_signature = OpenProfile.sha1(opts[:secret]+':'+header_string+':'+document)
      d.valid_signature = (test_signature == signature)
      
      return d
    end
    
  end
  
  
  
  class Provider
    
    attr_accessor :endpoint
    
    def initialize(opts)
      #@endpoint = nil || opts[:endpoint]
      #@secret   = false || opts[:secret]
      #@key      = false || opts[:key]
      
      puts opts.inspect
      
    end
    
    def handshake!(opts)
      #return {:status => 'Error', :message => 'From provider not given'} unless opts[:from].to_s.length > 0
      
      #Request.post('test', )
      
      #options = {
      #  :body => {
      #    :pear => { # your resource
      #      :foo => '123', # your columns/data
      #      :bar => 'second',
      #      :baz => 'last thing'
      #    }
      #  }
      #}
      #HTTParty.post('/pears.xml', options)
      
      #body = MultiJson.encode()
      #options = {
      #  :body => OpenProfile.sign()
      #}
      
      
      
      #Request.post(@endpoint+'/handshake/request', )
      
      return {}
    end
    
  end# module Provider
  
end # module OpenProfile
