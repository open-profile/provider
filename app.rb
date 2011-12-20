
get '/' do
  erb :index, :layout => :default
end

post '/test_handshake' do
  begin
    handshake = false
    return 'Error' unless params[:provider]
  
    provider = Provider.first :provider => params[:provider]
    if provider
      return 'Provider Already Exists: '+provider.inspect
    end
  
    handshake = Handshake.new :provider => params[:provider]
    handshake.save!
  
    response = handshake.request! :from => CONFIG[:provider][:url]
  
    if response.body['status'] = 'success'
      p = Provider.first :provider => handshake.provider
      if p
        p.key = handshake.key
        p.secret = handshake.secret
        p.save!
        return p.inspect
      end
    
      p = Provider.new
      p.key = handshake.key
      p.provider = handshake.provider
      p.secret = handshake.secret
      p.save!
    
      return p.inspect
    else
      return response.inspect
    end
    
  ensure
    handshake.delete
  end
end

post '/handshake/challenge' do
  signed = (request.body.read).strip
  handshake = nil
  
  headers   = OpenProfile::Document.headers(signed)
  handshake = Handshake.first(:key => headers[:key])
  document  = OpenProfile::Document.decode(signed, :secret => handshake.secret)
  
  challenge_response = OpenProfile.sha1(handshake.secret+':'+document.body['challenge'])
  
  if document.valid? and handshake
    return OpenProfile::Document.new(
      :headers => {:key => handshake.key, :secret => handshake.secret},
      :body => {:provider => CONFIG[:provider][:url], :response => challenge_response, :status => 'success'}
    ).encode
  else
    return OpenProfile.respond({
      :provider => CONFIG[:provider][:url],
      :status => 'failure',
      :message => 'Invalid document'
    })
  end
end

post '/handshake/request' do
  signed_document = (request.body.read).strip
  document = OpenProfile::Document.decode(signed_document)
  
  url    = document.body['provider']+'/handshake/challenge'
  key    = document.body['key']
  secret = document.body['secret']
  
  challenge          = OpenProfile.random_alphanumeric
  challenge_response = OpenProfile.sha1(document.body['secret']+':'+challenge)
  
  response = OpenProfile::Request.post_signed(url, {:key => key, :secret => secret}, {
    :provider => CONFIG[:provider][:url],
    :challenge => challenge,
  })
  
  if response.valid? and response.body['response'] == challenge_response and response.body['status'] == 'success'
    existing = Provider.first :provider => document.body['provider']
    if existing
      existing.key = key
      existing.secret = secret
      existing.save!
    else
      provider = Provider.new
      provider.key = key
      provider.provider = document.body['provider']
      provider.secret = secret
      provider.save!
    end
    
    return OpenProfile::Document.new(
      :headers => {:key => provider.key, :secret => provider.secret},
      :body => {:status => 'success'}
    ).encode
  else
    return OpenProfile::Document.new(
      :body => {:status => 'Failure', :message => 'Error performing challenge'}
    ).encode
  end
end
