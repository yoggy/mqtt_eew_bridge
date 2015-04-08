#!/usr/bin/ruby2.1
# -*- coding: utf-8 -*-
#
# mqtt_eew_bridge.rb - simple eew -> MQTT bridge 
#
# setup
#
#     $ git clone https://github.com/yoggy/mqtt_eew_bridge.git
#     $ cd mqtt_eew_bridge
#     $ sudo gem install eew_parser
#     $ sudo gem install mqtt
#     $ sudo gem install pit
#     $ EDITOR=vim ./mqtt_eew_bridge.rb
#
#         ---
#         wni_user: username
#         wni_pass: password
#         mqtt_host: mqtt.example.com
#         mqtt_port: 1883
#         mqtt_user: mqtt_username
#         mqtt_pass: mqtt_password
#         mqtt_topic: topic
#
# see also...
#     http://d.hatena.ne.jp/Glass_saga/20110421/1303388607
#
require 'rubygems'
require 'eew_parser'
require 'mqtt'
require 'pit'

require 'digest/md5'
require 'json'
require 'logger'
require 'open-uri'
require 'socket'
require 'securerandom'
require 'optparse'

$stdout.sync = true
$log = Logger.new(STDOUT)
$log.level = Logger::DEBUG

$config = Pit.get("mqtt_eew_bridge", :require => {
	"wni_user"   => "wni_user",
	"wni_pass"   => "wni_pass",
	"mqtt_host"  => "mqtt.example.com",
	"mqtt_port"  => 1883,
	"mqtt_user"  => "mqtt_user",
	"mqtt_pass"  => "mqtt_pass",
	"mqtt_topic" => "mqtt_topic",
})

# for MQTT
def mqtt_publish(message)
  topic = $config['mqtt_topic']
  $log.debug "topic=#{topic}, message=#{message}"

  catch :try_loop do
    10.times do
      begin
        mqtt = MQTT::Client.connect(
          :remote_host => $config['mqtt_host'],
          :remote_port => $config['mqtt_port'].to_i,
          :username    => $config['mqtt_user'],
          :password    => $config['mqtt_pass']
        )
        mqtt.publish(topic, message , retain=false)
        sleep(1)
        mqtt.disconnect()
        throw :try_loop
      rescue Exception => e
        $log.error(e)
      end
      sleep 0.5
    end
    $log.error "Failed to publish mqtt message...topic=#{topic}, message=#{message}"
  end
end

def send_keepalive()
  h = {}
  h['type'] = 'keepalive'
  mqtt_publish(JSON.generate(h))
end

def send_eew(eew)
  h = {}
  h['type'] = 'eew'
  h['eew']  = eew
  mqtt_publish(JSON.generate(h))
end

class WNI_EEW
  trap(:INT) do
    $log.info "exit..."
    exit
  end

  def initialize(user_id, pass)
    loop do
      begin
        initialize_inner(user_id, pass)
      rescue Exception => e
        $log.error e.to_s
        $log.error e.backtrace
      end
      $log.info "waiting... (10sec)"
      sleep 10
      $log.info "reconnectiong..."
    end
  end

  def initialize_inner(user_id, pass)
    (host,port) = get_server_list
    http = TCPSocket.open(host, port)
    http.print "GET /login HTTP/1.0\r\nX-WNI-Account: #{user_id}\r\nX-WNI-Password: #{Digest::MD5.hexdigest(pass)}\r\n\r\n"
    begin
      if WNI_HTTPHeader.new(http.readline("\n\n"))["X-WNI-Result"] == "OK"
        $log.info "connect success! #{host}:#{port}"
      else
        abort "authentication failed..."
      end
    rescue => ex
      abort "connection failed...#{ex.message}"
    end
    loop do
      case WNI_HTTPHeader.new(http.readline("\n\n"))["X-WNI-ID"]
      when "Keep-Alive"
        send_keepalive()
      when "Data"
        http.readline("\n\x02\n\x02\n")
        eew_str = http.readline("9999=").strip
        send_eew(eew_str)
      end
    end
    http.close
  end

  def get_server_list
    a = []
    open('http://lst10s-sp.wni.co.jp/server_list.txt') do |list|
      a = list.read.lines.to_a
    end
    a = a.map{|h| h.chomp.split(":")}
    a[SecureRandom.random_number(a.size)]
  end

  class WNI_HTTPHeader
    def initialize(str)
      @lines = str.lines.to_a
    end

    def [](key)
      @lines[1..-2].each do |line|
        field = line.split(":", 2)
        return field.last.strip if field.first == key
      end
    end
  end
end

#
# main
#
if __FILE__ == $0
  opt = OptionParser.new
  opt.on('-d', 'debug mode') {|v| @debug = true }
  opt.parse!(ARGV)

  if @debug
    eew_str = <<-EOS
37 03 01 120420065441 C11
120420065405
ND20120420065420 NCN004 JD////////////// JN///
289 N370 E1418 010 49 03 RK33513 RT10/// RC0////
EBI 360 S03// 065441 10 350 S03// ////// 10
9999=
EOS
    send_eew(eew_str)
  elsif
    WNI_EEW.new($config['wni_user'], $config['wni_pass'])
  end
end
