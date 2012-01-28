class Provider
  include MongoMapper::Document
  include OpenProfile::Server::Document
  
  key :key, String
  key :provider, String
  key :secret, String
  created_at_timestamp!
  
  def profile_handshake_request!(profile_url, from)
    response = OpenProfile::Request.post_signed(profile_url+'/handshake/request', {:key => self.key, :secret => self.secret}, {
      :provider => [CONFIG[:provider][:url]],
      :profile => [CONFIG[:provider][:url]+'/'+from.uid],
      :uid => from.uid
    })
    if response.valid? and response.body['status'] == 'success'
      handshake = Profile::Handshake.new
      handshake.to = response.body['profile'].first
      handshake.provider = self.provider
      handshake.status = 'pending'
      from.handshakes << handshake
      from.save!
    elsif !response.valid?
      puts response.inspect
      raise 'Invalid response!'
    else
      #puts response.inspect
      #raise 'Error sending handshake request!'
    end
    return response
  end
  
  def self.decode_document(body)
    headers = OpenProfile::Document.headers(body)
    
    raise 'No key found' unless headers[:key]
    key = headers[:key]
    
    provider = self.find_by_key(key)
    raise ('No provider found for key '+key+'!') unless provider
    
    return [provider, OpenProfile::Document.decode(body, :secret => provider.secret)]
  end
end