require 'rubygems'
require 'bundler/setup'
require File.expand_path '../paparazzi.rb', __FILE__
run Sinatra::Application
