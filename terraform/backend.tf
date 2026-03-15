terraform {
  backend "s3" {
    bucket         = "petclinic-tfstate-plopit"
    key            = "prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-lock"   # for state locking
    encrypt        = true
  }
}
