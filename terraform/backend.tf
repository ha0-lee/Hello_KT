terraform {
  backend "s3" {
    bucket         = "hellokt-terraform-state-985090322396"
    key            = "applunch/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}