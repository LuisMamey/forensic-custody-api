terraform {
  backend "s3" {
    bucket         = "forensic-custody-tfstate-737710548831"
    key            = "prod/forensic-custody-api.tfstate"
    region         = "us-east-1"
    dynamodb_table = "forensic-custody-tfstate-locks"
    encrypt        = true
  }
}
