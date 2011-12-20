class Provider
  include MongoMapper::Document
  include OpenProfile::Server::Document
  
  key :key, String
  key :provider, String
  key :secret, String
  created_at_timestamp!
  
end