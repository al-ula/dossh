#!/usr/bin/env fish
set ip_address (curl -s ifconfig.me)
echo "The current IP address is:" (set_color blue)$ip_address(set_color normal)

set firewall_list (doctl compute firewall list --format ID,Name --no-header)
for line in $firewall_list
  set id (echo $line | awk '{print $1}')
  set name (echo $line | awk '{print $2}')
end

echo "Updating firewall "(set_color yellow)$name(set_color normal)" to change allowed inbound SSH to current IP"

set current_inbound (doctl compute firewall get $id --format InboundRules --no-header)
set current_inbound (string split ' ' -- $current_inbound)
set current_outbound (doctl compute firewall get $id --format OutboundRules --no-header)
set current_outbound (string split ' ' -- $current_outbound)

echo "Current inbound rules:"
for rule in $current_inbound
  echo "  "$rule
end

echo "Current outbound rules:"
for rule in $current_outbound
  echo "  "$rule
end

for i in (seq 1 (count $current_inbound))
    set rule $current_inbound[$i]
    if string match -q 'protocol:tcp,ports:22,*' $rule
        set -a inbound_ruleset "protocol:tcp,ports:22,address:$ip_address"
        echo "Replacing ssh rule..."
    else
        set -a inbound_ruleset $current_inbound[$i]
    end

end

echo "New inbound rules:"
for rule in $inbound_ruleset
  echo "  "$rule
end

set inbound_rules $inbound_ruleset
set outbound_rules $current_outbound
set response (doctl compute firewall update $id --name $name --inbound-rules "$inbound_rules" --outbound-rules "$outbound_rules" --format Name,Status --no-header)

set response_status (echo $response | awk '{print $2}')
if test $response_status = "succeeded"
    set status_color green
else
    set status_color red
end
echo "Updating" (set_color yellow)(echo $response | awk '{print $1}')(set_color normal) "is" (set_color $status_color)$response_status(set_color normal)
