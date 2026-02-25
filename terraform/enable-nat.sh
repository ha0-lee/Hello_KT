terraform apply \
  -target=aws_eip.nat_eip \
  -target=aws_nat_gateway.nat_gw \
  -target=aws_route.private_internet_route \
  -auto-approve

  # power shell에서 실행할 때는 아래 명령어로 실행
  # terraform apply -target aws_eip.nat_eip -target aws_nat_gateway.nat_gw -target aws_route.private_internet_route -auto-approve