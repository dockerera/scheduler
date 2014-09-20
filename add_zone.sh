#!/bin/bash
# Get Container Details for DNS
    ENV['CONTAINER_IP_ADDR']  = %x{docker inspect $CONTAINER_CID_LONG | grep '"IPAddress"'}.strip.gsub(/[^0-9\.]/i, '')
    ENV['CONTAINER_HOSTNAME'] = %x{docker inspect $CONTAINER_CID_LONG| grep '"Hostname"' | awk '{print $NF}'}.strip.gsub(/^"(.*)",/i, '\1')

    puts ENV['CONTAINER_HOSTNAME']
    puts ENV['CONTAINER_IP_ADDR']

    # Get Process ID of the LXC Container
    ENV['NSPID'] = %x{head -n 1 $(find "$CGROUPMNT" -name $CONTAINER_CID_LONG | head -n 1)/tasks}.strip

    # Ensure we have the PID
    unless ENV['NSPID']
      log.error "Could not find a process indentifier for container #{ENV['CONTAINER_CID']}. Cannot update DNS."
      next
    end

    # Create the Net Namespaces
    %x{mkdir -p /var/run/netns}
    %x{rm -f /var/run/netns/$NSPID}
    %x{ln -s /proc/$NSPID/ns/net /var/run/netns/$NSPID}

    # Build the command to update the dns server
    update_command = <<-UPDATE
    ip netns exec $NSPID nsupdate -k $DDNS_KEY <<-EOF
    server $NET_NS
    zone $NET_DOMAIN.
    update delete $CONTAINER_HOSTNAME.$NET_DOMAIN
    update add $CONTAINER_HOSTNAME.$NET_DOMAIN 60 A $CONTAINER_IP_ADDR
    send
    EOF
    UPDATE

    # Run the nameserver update in the Net Namespace of the LXC Container
    system(update_command.gsub(/^[ ]{4}/, ''))

    # Message an success
    if $?.success?
      log.info "Updated Docker DNS (#{ENV['CONTAINER_CID']}): #{ENV['CONTAINER_HOSTNAME']}.#{ENV['NET_DOMAIN']} 60 A #{ENV['CONTAINER_IP_ADDR']}."
    else
      log.error "We could not update the Docker DNS records for #{ENV['CONTAINER_CID']}. Please check your nsupdate keys."
    end
