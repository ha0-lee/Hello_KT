terraform destroy \
  -target=aws_route.private_internet_route \
  -target=aws_nat_gateway.nat_gw \
  -target=aws_eip.nat_eip \
  -auto-approve

  # power shell에서 실행할 때는 아래 명령어로 실행
  # terraform destroy -target aws_route.private_internet_route -target aws_nat_gateway.nat_gw -target aws_eip.nat_eip -auto-approve