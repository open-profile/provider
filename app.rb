
helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

get '/' do
  @me = Profile.first
  
  erb :index, :layout => :default
end

post '/test_handshake' do
  begin
    handshake = false
    return 'Error' unless params[:provider]
    
    provider = Provider.first :provider => params[:provider]
    if provider
      return 'Provider Already Exists: '+h(provider.inspect)
    end
    
    handshake = Handshake.new :provider => params[:provider]
    handshake.save!
    
    response = handshake.request! :from => CONFIG[:provider][:url]
    
    if response.body['status'] == 'success'
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
      return h(response.inspect)
    end
  ensure
    handshake.delete if handshake
  end
end


post '/test_profile_handshake' do
  me = Profile.first
  profile = OpenProfile::Profile.lookup(params[:profile])
  provider = Provider.find_by_provider(profile.body['provider'].first)
  
  return 'Error! No handshake with '+profile.body['provider'].first+'!' unless provider
  
  response = provider.profile_handshake_request!(profile.body['profile'].first, me)
  
  if response.body['status'] == 'success'
    return 'Request sent.'
  else
    return 'Error sending request: '+h(response.body['message'])
  end
end

get '/profile/:profile/handshake/:handshake/accept' do
  @profile   = Profile.find(params[:profile])
  @handshake = @profile.handshakes.find(params[:handshake])
  
  response = @handshake.accept!
  return h(response.inspect)
end
get '/profile/:profile/handshake/:handshake/deny' do
  @profile   = Profile.find(params[:profile])
  @handshake = @profile.handshakes.find(params[:handshake])
  
  return h(@handshake.inspect)
end








post '/handshake/challenge' do
  signed = (request.body.read).strip
  handshake = nil
  
  headers   = OpenProfile::Document.headers(signed)
  handshake = Handshake.first(:key => headers[:key])
  document  = OpenProfile::Document.decode(signed, :secret => handshake.secret)
  
  challenge_response = OpenProfile.sha1(handshake.secret+':'+document.body['challenge'])
  
  puts document.inspect
  puts handshake.inspect
  
  if document.valid? and handshake
    return OpenProfile::Document.new(
      :headers => {:key => handshake.key, :secret => handshake.secret},
      :body => {:provider => [CONFIG[:provider][:url]], :response => challenge_response, :status => 'success'}
    ).encode
  else
    return OpenProfile.respond({
      :provider => [CONFIG[:provider][:url]],
      :status => 'error',
      :message => 'Invalid document'
    })
  end
end

post '/handshake/request' do
  signed_document = (request.body.read).strip
  document = OpenProfile::Document.decode(signed_document)
  
  url    = document.body['provider'].first+'/handshake/challenge'
  key    = document.body['key']
  secret = document.body['secret']
  
  challenge          = OpenProfile.random_alphanumeric
  challenge_response = OpenProfile.sha1(document.body['secret']+':'+challenge)
  
  response = OpenProfile::Request.post_signed(url, {:key => key, :secret => secret}, {
    :provider => [CONFIG[:provider][:url]],
    :challenge => challenge,
  })
  
  if response.valid? and response.body['response'] == challenge_response and response.body['status'] == 'success'
    existing = Provider.first :provider => document.body['provider'].first
    if existing
      existing.key = key
      existing.secret = secret
      existing.save!
    else
      provider = Provider.new
      provider.key = key
      provider.provider = document.body['provider'].first
      provider.secret = secret
      provider.save!
    end
    
    return OpenProfile::Document.new(
      :headers => {:key => provider.key, :secret => provider.secret},
      :body => {:status => 'success'}
    ).encode
  else
    return OpenProfile::Document.new(
      :body => {:status => 'error', :message => 'Error performing challenge'}
    ).encode
  end
end




post '/:uid/handshake/request' do
  #document = OpenProfile::Document.decode(request.body.read.strip)
  provider, document = Provider.decode_document(request.body.read.strip)
  
  me = Profile.find_by_uid(params[:uid])
  if handshakes = me.handshakes.select {|h| h.from == document.body['profile'].first and h.provider == provider.provider } and handshakes.length > 0
    return OpenProfile::Document.new(
      :body => {:status => 'error', :message => 'Request already sent'}
    ).encode
  end
  
  handshake = Profile::Handshake.new
  handshake.from = document.body['profile'].first
  handshake.provider = provider.provider
  handshake.status = 'pending'
  me.handshakes << handshake
  if me.save
    return OpenProfile::Document.new(
      :headers => {:key => provider.key, :secret => provider.secret},
      :body => {
        :uid => me.uid,
        :provider => [CONFIG[:provider][:url]],
        :profile => [me.profile_url],
        :status => 'success'
      }
    ).encode
  else
    return OpenProfile::Document.new(
      :body => {:status => 'error', :message => 'Error receiving request'}
    ).encode
  end
end
post '/:uid/handshake/accept' do
  provider, document = Provider.decode_document(request.body.read.strip)
  
  @me = Profile.find_by_uid(params[:uid])
  # Handshakes matching the request
  inbound_handshakes = @me.handshakes.select {|h| h.to == document.body['profile'].first and h.provider == provider.provider }
  
  # See if the handshake has already been accepted
  accepted_handshakes = inbound_handshakes.select {|h| h.status == 'accepted' }
  if accepted_handshakes.length > 0
    return OpenProfile::Document.new(:body => {:status => 'error', :message => 'Handshake already accepted', :code => 410}).encode
  end
  
  # Subset of pending handshakes
  handshakes = inbound_handshakes.select {|h| h.status == 'pending' }
  if handshakes.length == 0
    return OpenProfile::Document.new(:body => {:status => 'error', :message => 'Handshake request not found', :code => 404}).encode
  end
  
  # Delete extra handshakes (in case any were made)
  handshakes.slice(1, handshakes.length).each {|h| h.destroy }
  
  handshake = handshakes.first
  handshake.status = 'accepted'
  handshake.accepted_at = Time.now
  if @me.save
    #return OpenProfile::Document.new(
    #  :headers => {:key => provider.key, :secret => provider.secret},
    #  :body => {
    #    :uid => @me.uid,
    #    :provider => [CONFIG[:provider][:url]],
    #    :profile => [@me.profile_url],
    #    :status => 'success'
    #  }
    #).encode
    return @me.document_for(provider, :body => {:status => 'success'}).encode
  else
    return OpenProfile::Document.new(:body => {:status => 'error', :message => 'Error accepting request'}).encode
  end
end
# Can be used both to deny a request and cancel an existing handshake.
post '/:uid/handshake/deny' do
  provider, document = Provider.decode_document(request.body.read.strip)
  
  @me = Profile.find_by_uid(params[:uid])
  # Handshakes matching the request
  handshakes = @me.handshakes.select {|h| h.to == document.body['profile'].first and h.provider == provider.provider }
  if handshakes.length == 0
    return OpenProfile::Document.new(:body => {:status => 'error', :message => 'Handshake not found', :code => 404}).encode
  end
  
  # Delete extra handshakes (in case any were made)
  handshakes.slice(1, handshakes.length).each {|h| h.destroy }
  
  handshake = handshakes.first
  handshake.status = 'denied'
  if @me.save
    #return OpenProfile::Document.new(
    #  :headers => {:key => provider.key, :secret => provider.secret},
    #  :body => {
    #    :uid => @me.uid,
    #    :provider => [CONFIG[:provider][:url]],
    #    :profile => [@me.profile_url],
    #    :status => 'success'
    #  }
    #).encode
    return @me.document_for(provider, :body => {:status => 'success'}).encode
  else
    return OpenProfile::Document.new(:body => {:status => 'error', :message => 'Error denying handshake'}).encode
  end
end

get '/:uid' do
  p = Profile.find_by_uid(params[:uid])
  return OpenProfile::Document.new(
    :body => {:uid => p.uid, :provider => [CONFIG[:provider][:url]], :profile => [CONFIG[:provider][:url]+'/'+p.uid]}
  ).encode
end

