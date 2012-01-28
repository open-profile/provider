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
  
  class Handshake
    include MongoMapper::EmbeddedDocument
    include OpenProfile::Server::Document
    
    key :to, String,   :default => nil
    key :from, String, :default => nil
    key :provider, String
    key :status, String, :default => 'pending'
    created_at_timestamp!
    
    validates_presence_of :provider
    validates_presence_of :status
    
    #belongs_to :profile
    embedded_in :profile
  end
end
