require 'rubygems'
require 'bundler'

Bundler.require

MONGO_CONNECTION = Mongo::Connection.from_uri(CONFIG[:database][:url])
#MONGO_DATABASE   = MONGO_CONNECTION.db(CONFIG[:database][:name])
MongoMapper.connection = MONGO_CONNECTION
MongoMapper.database   = CONFIG[:database][:name]

APP_ROOT = ::File.dirname(__FILE__)
APP_ENV  = ENV['RACK_ENV'] or 'development'

require APP_ROOT+'/lib'

require APP_ROOT+'/app/model'
['handshake', 'provider'].each do |model|
  require APP_ROOT+'/app/models/'+model
end
