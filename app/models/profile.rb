class Profile
  include MongoMapper::Document
  include OpenProfile::Server::Document
  
  key :uid, String
  created_at_timestamp!
  
  many :handshakes, :class_name => 'Profile::Handshake'
  
  validates_presence_of :uid
  validates_length_of :uid, :minimum => 1, :maximum => 32
  
  def profile_url
    CONFIG[:provider][:url]+'/'+self.uid
  end
  
  def document_to(provider, opts = {})
    d = OpenProfile::Document.new(
      :headers => {:key => provider.key, :secret => provider.secret},
      :body => {
        :uid => self.uid,
        :provider => [CONFIG[:provider][:url]],
        :profile => [self.profile_url]
      }
    )
    if opts[:body].is_a? Hash
      d.body.merge! opts[:body]
    end
    
    return d
  end
  alias :document_for :document_to
  
  class Handshake
    include MongoMapper::EmbeddedDocument
    include OpenProfile::Server::Document
    
    key :to, String,   :default => nil
    key :from, String, :default => nil
    key :provider, String
    key :status, String, :default => 'pending'
    key :accepted_at, Time
    created_at_timestamp!
    
    validates_presence_of :provider
    validates_presence_of :status
    
    #belongs_to :profile
    embedded_in :profile
    
    def destroy
      p = self.profile
      p.handshakes = p.handshakes.select {|h| h.id != self.id }
      p.save!
    end
    
    def ui_accept_url
      '/profile/'+self.profile.id.to_s+'/handshake/'+self.id.to_s+'/accept'
    end
    def ui_deny_url
      '/profile/'+self.profile.id.to_s+'/handshake/'+self.id.to_s+'/deny'
    end
    
    def accept!
      p = Provider.find_by_provider(self.provider)
      response = OpenProfile::Request.post_signed(self.from+'/handshake/accept', {:key => p.key, :secret => p.secret}, {
        :provider => [CONFIG[:provider][:url]],
        :profile => [CONFIG[:provider][:url]+'/'+self.profile.uid],
        :uid => self.profile.uid
      })
      if response.valid? and response.body['status'] == 'success'
        self.status = 'accepted'
        self.accepted_at = Time.now
        self.save!
      elsif !response.valid?
        puts response.inspect
        raise 'Invalid response!'
      elsif not (response.body['status'] == 'error' and response.body['code'] == 410)
        # 410 is a request already accepted response, so don't raise an exception for that.
        puts response.inspect
        raise 'Error sending handshake acceptance!'
      end
      return response
    end
    
    def other
      self.to or self.from
    end
  end
end
