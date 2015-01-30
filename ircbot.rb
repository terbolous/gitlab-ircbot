#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'sinatra/base'
require 'cinch'
require 'json'
require 'yaml'

$config = YAML.load_file('config.yml')
channels = $config['gitlab'].values.map { |c| c['channel']}

class App < Sinatra::Application
  class << self
    attr_accessor :ircbot
  end
  @@ircbot = nil


  configure do
    set :bind, '0.0.0.0'
    set :port, $config['sinatra']['port']
    disable :traps
  end

  post '/commit' do
    data = JSON.parse request.body.read
    project_name = data['repository']['name']

    if $config['gitlab'].include? project_name
      ch = $config['gitlab'][project_name]['channel']
      send = nil
      unless data['ref'].include? 'ref/tags'
        # FIXME: chec if this is commit or tag
        commit = data['commits'][0]
        commit_message = commit['message'].gsub(/\n/," ")
        user = commit['author']['name']
        commit_sha = commit['id'][0..8]
        commit_url = commit['url']
        send  = "[#{project_name.capitalize}] #{user} | #{commit_message} | View Commit: #{commit_url}"
      elsif data['ref'].include? 'refs/tags'
        # Fetch tag from 'refs/tags/<our tag>'
        tag = data['ref'].split('/')[2]
        url = data['repository']['homepage'] + '/tree/' + tag

        send = "[#{project_name.capitalize}] New Tag: #{tag} | View Tag: #{url}"
      end

      if send.is_a? String
        App.ircbot.Channel(ch).send(send)
      end


    end
    status 200
    body "Thank you"
  end
end

bot = Cinch::Bot.new do
  configure do |c|
    c.load! $config['irc']
    c.channels = channels
  end
end
bot.loggers.first.level = :info

App.ircbot = bot

t_bot = Thread.new {
  bot.start
}

t_app = Thread.new {
  App.start!
}

trap_block = proc {
  App.quit!
  Thread.new {
    bot.quit
  }
}

Signal.trap("SIGINT", &trap_block)
Signal.trap("SIGTERM", &trap_block)

t_bot.join
