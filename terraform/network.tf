# VPC, Subnet, IGW, NAT, ALB (인프라 뼈대)

# 1. VPC 생성
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "Main-VPC" }
}

# 2. 서브넷 생성 (고가용성을 위해 2개의 가용영역 사용)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1" }
}
# public_1 밑에 추가하세요
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-2a"
  tags              = { Name = "Private-Subnet-1" }
}
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-2b"
  tags              = { Name = "Private-Subnet-2" }
}
# 2번 프라이빗 서브넷 추가 (장애 대응용)
resource "aws_subnet" "private_3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-northeast-2c"
  tags              = { Name = "Private-Subnet-3" }
}
# 3. 인터넷 관문 (Public용)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# 1. NAT가 사용할 고정 IP(EIP) 하나 예약
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# 2. NAT 게이트웨이 생성 (반드시 퍼블릭 서브넷에 두어야 함)
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id # 입구는 퍼블릭에!
  tags          = { Name = "Main-NAT" }
}

# 3. 프라이빗 전용 라우팅 테이블 (프라이빗 서버들을 위한 지도)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id # 인터넷 나갈 거면 NAT로 가라!
  }
}
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

# 4. 프라이빗 서브넷에 이 지도를 쥐어주기
resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "private_assoc_3" {
  subnet_id      = aws_subnet.private_3.id
  route_table_id = aws_route_table.private_rt.id
}

# 1. 로드밸런서 본체

# resource "aws_lb" "web_alb" {
#   name               = "web-app-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.web_sg.id]
#   subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id] # ALB는 서브넷 2개 이상 필요
# }
# 로드밸런서의 DNS 주소 출력

# output "alb_dns_name" {
#   value = aws_lb.web_alb.dns_name
# }

# 2. 대상 그룹 (앱 서버들을 담는 바구니)

# resource "aws_lb_target_group" "app_tg" {
#   name     = "app-target-group"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.main.id

#   health_check {
#     path     = "/" # 서버의 "/" 경로가 정상인지 체크
#     protocol = "HTTP"
#     matcher  = "200" # 응답 코드가 200이면 "살아있음!"
#     interval = 30
#   }
# }

# 3. 리스너 (80포트로 오면 대상 그룹으로 전달)
# resource "aws_lb_listener" "http" {
#   load_balancer_arn = aws_lb.web_alb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg.arn
#   }
# }

# 4. 앱 서버들을 로드밸런서에 연결
# resource "aws_lb_target_group_attachment" "app_attach" {
#   count            = 2
#   target_group_arn = aws_lb_target_group.app_tg.arn
#   target_id        = aws_instance.web_server[count.index].id
#   port             = 80
# }

