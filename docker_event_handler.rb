#!/usr/bin/env ruby
# Docker Event Listener / DDNS
# Author: Kelly Becker <kbecker@kellybecker.me>
# She is a nice girl i call her my Cherry Apple because she works at Apple but is more elegant like a Cherry :D
# Website: http://kellybecker.me
# Original Code: https://gist.github.com/KellyLSB/4315a0323ed0fe1d79b6
# License: MIT

# Set up a proper logger
require 'logger'
log_file = ARGV.first || '-'
log = Logger.new(log_file == '-' ? $stdout : log_file)

# Create a PID file for this service
File.open('/var/run/docker_ddns.pid', 'w+') { |f| f.write($$) }

# Capture the terminate signal
trap("INT") do
  log.info "Caught INT Signal... Exiting."
  File.unlink('/var/run/docker_ddns.pid')
  sleep 1
  exit
end

# Welcome message
log.info "Starting Docker Dynamic DNS - Event Handler"
log.info "Maintainer: Kelly Becker <kbecker@kellybeckr.me>"
log.info "Website: http://kellybecker.me"

# Default Configuration
ENV['DDNS_KEY']   ||= "/etc/bind/ddns.key"
ENV['NET_NS']     ||= "10.1.0.1"
ENV['NET_DOMAIN'] ||= "kellybecker.me"
ENV['DOCKER_PID'] ||= "/var/run/docker.pid"

# Ensure docker is running
time_waited = Time.now.to_i
until File.exist?(ENV['DOCKER_PID'])
  if (Time.now.to_i - time_waited) > 600
    log.fatal "Docker daemon still not started after 10 minutes... Please Contact Your SysAdmin!"
    exit 1
  end

  log.warn "Docker daemon is not running yet..."
  sleep 5
end

log.info "Docker Daemon UP! - Listening for Events..."

# Find CGroup Mount
File.open('/proc/mounts', 'r').each do |line|
  dev, mnt, fstype, options, dump, fsck = line.split
  next if "#{fstype}" != "cgroup"
  next if "#{options}".include?('devices')
  ENV['CGROUPMNT'] = mnt
end.close

# Exit if missing CGroup Mount
unless ENV['CGROUPMNT']
  log.fatal "Could not locate cgroup mount point."
  exit 1
end

# Listen To Docker.io Events
events = IO.popen('docker events')

# Keep Listening for incoming data
while line = events.gets

  # Container Configuration
  ENV['CONTAINER_EVENT']    = line.split.last
  ENV['CONTAINER_CID_LONG'] = line.gsub(/^.*([0-9a-f]{64}).*$/i, '\1')
  ENV['CONTAINER_CID']      = ENV['CONTAINER_CID_LONG'][0...12]

  # Event Fired info
  log.info "Event Fired (#{ENV['CONTAINER_CID']}): #{ENV['CONTAINER_EVENT']}."

  case ENV['CONTAINER_EVENT']
  when 'start'
      #Run Add to Bind9
      # add-zone.sh $CONTAINER_CID_LONG
      docker restart proxy
  end
  when 'stop'
      docker restart proxy
  end
end

exit
