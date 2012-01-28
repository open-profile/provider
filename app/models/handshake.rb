class Handshake
  include MongoMapper::Document
  include OpenProfile::Server::Document
  
  key :key, String
  key :provider, String
  key :secret, String
  created_at_timestamp!
  
  #before_save :update_created_at
  #def update_created_at
  #  now = Time.now.utc
  #  self[:created_at] = now if !persisted? && !created_at?
  #  self[:updated_at] = now
  #end
  
  validates_presence_of :key
  validates_presence_of :provider
  validates_presence_of :secret
  
  
  def initialize(*args)
    super(*args)
    
    self.key = OpenProfile.random_alphanumeric unless self.key
    self.secret = OpenProfile.random_alphanumeric unless self.secret
  end
  
  def request!(opts)
    challenge = OpenProfile.random_alphanumeric
    
    response = OpenProfile::Request.post_signed(self.provider+'/handshake/request', self.attributes, {
      :provider => [opts[:from]],
      :secret => self.secret,
      :key => self.key
    })
    
  end
end
