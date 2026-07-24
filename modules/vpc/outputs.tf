output "vpc_id" {
  description = "ID de la VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR de la VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs de las subnets públicas."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de las subnets privadas."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "Elastic IPs de los NAT Gateways."
  value       = aws_eip.nat[*].public_ip
}

output "internet_gateway_id" {
  description = "ID del Internet Gateway."
  value       = aws_internet_gateway.this.id
}
