#!/usr/bin/ruby1.9.3
# -*- coding: utf-8 -*-
#
# $ sudo gem install eew_parser --no-ri --no-rdoc
#
# see also...
#   http://d.hatena.ne.jp/Glass_saga/20110421
#   https://github.com/Glasssaga/eew_parser
#   http://glasssaga.dip.jp/eew_parser_doc/EEWParser.html
#   http://eew.mizar.jp/excodeformat
#
require 'rubygems'
require 'socket'
require 'eew_parser'
require 'digest/md5'
require 'open-uri'
require 'net/netrc'
require 'xmpp4r'
require 'securerandom'
require_relative './nma_jishin_notify'

require 'optparse'
require 'pp'

# configuration...
@gtalk_rc = Net::Netrc.locate("gtalk_jishin")
@wni_rc = Net::Netrc.locate("wni")
@target_area = ["東京","神奈川"]
@notifiy_magnitude = 5.0
@notify_gtalk_users = ['yoggy0@gmail.com']

puts @gtalk_rc.login, @gtalk_rc.password

Jabber.debug = true

class EEWParser
  def subject
    msg = ""
    msg += "【訓練】" if drill_type =~ /訓練/

    msg += "【緊急地震速報】#{epicenter}M#{magnitude}"
    msg
  end

  def message
    msg = subject + "\n\n"
    msg += <<-"EOS"
地震発生時刻: #{earthquake_time.strftime("%H:%M:%S")}

EOS
    ebi.each do |local|
      msg += "#{local[:area_name]}:\n"
      t = "到達時刻不明"
      t = "到達まであと#{(local[:arrival_time] - Time.now).to_i}秒" unless local[:arrival_time].nil?
      msg += "震度#{local[:intensity]} #{t}\n"
    end
    msg += <<-"EOS2"

訓練等の識別符: #{drill_type}
発表状況（訂正等）の指示: #{status}
EOS2
    msg
  end
end

class WNI_EEW
  DEBUG = true

  trap(:INT) do
    puts "exit..."
    exit
  end

  def initialize(user_id, pass, &b)
    loop do
      begin
        initialize_inner(user_id, pass, &b)
      rescue Exception => e
        debug e.to_s
        debug e.backtrace
      end
      debug "waiting...10seconds"
      sleep 10
      debug "reconnectiong..."
    end
  end

  def initialize_inner(user_id, pass, &b)
    (host,port) = get_server_list
    http = TCPSocket.open(host, port)
    http.print "GET /login HTTP/1.0\r\nX-WNI-Account: #{user_id}\r\nX-WNI-Password: #{Digest::MD5.hexdigest(pass)}\r\n\r\n"
    begin
      if WNI_HTTPHeader.new(http.readline("\n\n"))["X-WNI-Result"] == "OK"
        debug "[#{Time.now.strftime("%F %T")}] connect success! #{host}:#{port}"
      else
        abort "authentication failed..."
      end
    rescue => ex
      abort "connection failed...#{ex.message}"
    end
    loop do
      case WNI_HTTPHeader.new(http.readline("\n\n"))["X-WNI-ID"]
      when "Keep-Alive"
        debug "[#{Time.now.strftime("%F %T")}] Keep-Alive"
      when "Data"
        debug "[#{Time.now.strftime("%F %T")}] Data"
        http.readline("\n\x02\n\x02\n")
        msg = http.readline("9999=").strip
        pp msg
        yield EEWParser.new(msg)
      end
    end
    http.close
   end

  def debug(str)
    puts str if DEBUG
    $stdout.flush if DEBUG
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
#
#
def jishin_notify_gtalk(eew)
  begin
    # connect google talk for bot
    gtalk = Jabber::Client.new(Jabber::JID.new("#{@gtalk_rc.login}"))
    gtalk.connect('talk.google.com', 5222)
    gtalk.auth(@gtalk_rc.password)
    gtalk.send(Jabber::Presence.new.set_show(:chat))
    
    @notify_gtalk_users.each do |u|
      msg = Jabber::Message.new(u)
      msg.body = eew.message
      gtalk.send(msg)
    end
  rescue Exception => e
    p e
    p e.backtrace
  end
end

#
#
#
def jishin_notify_nma(eew)
  nma = NMAJishinNotify.new("3ccab95d9b5afc180261fae22e6fe4d7ee31b9e5d2573183", "JISHIN Notifier")
  nma.send(eew.subject, eew.message, 2)
end

#
#
#
def jishin_notify_ssh_gntp(eew)
  msg = eew.message
  msg.gsub!(/\n/, "_")
  msg.gsub!(/\s/, "_")

  cmd = "ssh dns00.piecake.com /home/sukedai/bin/jishin_notify_gntp.rb '#{eew.subject}' '#{msg}'"
  puts "cmd : " + cmd
  system(cmd)
end

#
#
#
def jishin_notify(eew)
  puts eew.message
  jishin_notify_gtalk(eew)
  jishin_notify_nma(eew)
  jishin_notify_ssh_gntp(eew)
end

#
#
#
def process_eew(eew)
  msg = eew.message
  
  notify_flag = false
  @target_area.each do |area|
    reg = Regexp.new(area)
    notify_flag = true if msg =~ reg
  end
  
  notify_flag = true if eew.magnitude >= @notifiy_magnitude
  
  if notify_flag
    jishin_notify(eew)
  end
  
  $stdout.flush
end



#
# main
#
@debug = false
if __FILE__ == $0
  opt = OptionParser.new
  opt.on('-d', 'debug mode') {|v| @debug = true }
  opt.parse!(ARGV)

  if @debug
    str = <<-EOS
37 03 01 120420065441 C11
120420065405
ND20120420065420 NCN004 JD////////////// JN///
289 N370 E1418 010 49 03 RK33513 RT10/// RC0////
EBI 360 S03// 065441 10 350 S03// ////// 10
9999=
EOS
    eew = EEWParser.new(str)
    process_eew(eew)
  elsif
    WNI_EEW.new(@wni_rc.login, @wni_rc.password) do |eew|
      process_eew(eew)
    end
  end
end
