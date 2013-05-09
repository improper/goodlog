#!/usr/bin/env ruby19
#
# Simple 'tail -f' example.
# Usage example:
#   tail.rb /var/log/messages

# require 'rubygems'
require 'eventmachine'
require 'eventmachine-tail'
require 'pg'

class Traffic
  attr_reader :config
  attr_accessor :host_bytes

  def initialize
    @host_bytes = {}
    @config = eval(File.open('traffic.conf.rb').read)
    puts "config: #{@config}"
    @db = PG::Connection.open(@config[:postgresql])
    begin
      @db.exec('CREATE TABLE traffic (
                  hostname VARCHAR(200),
                  month INTEGER,
                  year INTEGER,
                  bytes INTEGER,
                  PRIMARY KEY (hostname, month, year)
                )')
    rescue PG::Error => e
      # table does exist
    end
  end

  def increment_host(hostname, bytes)
    @host_bytes[hostname] ||= 0
    @host_bytes[hostname] += bytes
  end

  def update_db
    puts "update db"
  end
end

class Reader < EventMachine::FileTail
  def initialize(path, startpos=-1, traffic)
    super(path, startpos)
    puts "Tailing #{path}"
    @buffer = BufferedTokenizer.new
    @traffic = traffic
  end

  def receive_data(data)
    @buffer.extract(data).each do |line|
      puts "#{path}: #{line}"
      m = line.match(/(?<hostname>\S+) (?<request_bytes>\d+) (?<response_bytes>\d+)/)
      hostname = m['hostname']
      bytes_total = m['request_bytes'].to_i + m['response_bytes'].to_i
      puts "host: #{m["hostname"]} bytes: #{bytes_total}"
      @traffic.increment_host(hostname, bytes_total)
      puts "host_bytes: #{@traffic.host_bytes[hostname]}"
    end
  end
end

def main(args)
  EM.run do
    traffic = Traffic.new
    traffic.config[:logfiles].each do |path|
      EM::file_tail(path, Reader, traffic)
    end
    EM.add_periodic_timer(traffic.config[:update_interval]) do
      traffic.update_db
    end
  end
end # def main

exit(main(ARGV))
