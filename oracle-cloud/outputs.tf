output "instance_public_ip" {
  description = "Public IP of the VPN server"
  value       = oci_core_instance.vpn.public_ip
}

output "instance_id" {
  description = "OCI instance OCID"
  value       = oci_core_instance.vpn.id
}

output "ssh_command" {
  description = "SSH to check status (optional)"
  value       = "ssh ubuntu@${oci_core_instance.vpn.public_ip}"
}

output "get_configs" {
  description = "Command to retrieve VPN client configs"
  value       = "ssh ubuntu@${oci_core_instance.vpn.public_ip} 'sudo docker compose -f /opt/family-vpn/docker-compose.yml exec vpn /entrypoint.sh configs'"
}

output "check_logs" {
  description = "Command to check VPN deployment logs"
  value       = "ssh ubuntu@${oci_core_instance.vpn.public_ip} 'cat /var/log/vpn-deploy.log; sudo docker compose -f /opt/family-vpn/docker-compose.yml logs --tail 20'"
}
