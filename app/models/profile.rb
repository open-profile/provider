class Provider
  include MongoMapper::Document
  include OpenProfile::Server::Document
  
  key :uid, String
  created_at_timestamp!
end
