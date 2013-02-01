require 'rubygems'
require 'bundler'
require 'time'
Bundler.require

require './devdigest'

task :run do
  since = Time.now-24*60*60
  Devdigest.run(since)
end