## -----------------------------------------------------
## VPC
## -----------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

## -----------------------------------------------------
## Internet Gateway
## -----------------------------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

## -----------------------------------------------------
## Public Subnets
## -----------------------------------------------------

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    {
      Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
      Tier = "public"
    },
    var.public_subnet_tags
  )
}

## -----------------------------------------------------
## Private Subnets
## -----------------------------------------------------

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    {
      Name = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
      Tier = "private"
    },
    var.private_subnet_tags
  )
}

## -----------------------------------------------------
## NAT Gateway(s)
## -----------------------------------------------------

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name_prefix}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

## -----------------------------------------------------
## Route Tables — Public
## -----------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

## -----------------------------------------------------
## Route Tables — Private
## -----------------------------------------------------

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.name_prefix}-rt-private-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

## -----------------------------------------------------
## VPC Flow Logs (Security best practice)
## -----------------------------------------------------

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  iam_role_arn             = aws_iam_role.flow_log.arn
  log_destination          = aws_cloudwatch_log_group.flow_log.arn
  log_destination_type     = "cloud-watch-logs"
  max_aggregation_interval = 60

  tags = {
    Name = "${var.name_prefix}-flow-log"
  }
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name              = "/aws/vpc-flow-log/${var.name_prefix}"
  retention_in_days = 30

  tags = {
    Name = "${var.name_prefix}-flow-log-group"
  }
}

resource "aws_iam_role" "flow_log" {
  name = "${var.name_prefix}-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.name_prefix}-vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}
