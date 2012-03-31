# Be sure to restart your web server when you modify this file.

# Load the rails application
require File.expand_path('../application', __FILE__)

path = Rails.root.join("config/options.yml")

begin
  CONFIG = YAML.load_file(path)
rescue Exception => e
  puts "Error while parsing config file #{path}"
  CONFIG = Hash.new
  raise e
end

CONFIG['apidocs_location'] ||= File.expand_path("../../docs/api/html/")
CONFIG['schema_location'] ||= File.expand_path("public/schema")+"/"
CONFIG['download_url'] ||= 'http://download.opensuse.org/repositories'

ActionController::Base.perform_caching = true
#ActiveRbac.controller_layout = "rbac"

# Initialize the rails application
OBSApi::Application.initialize!

