terraform {
  backend "s3" {
    bucket  = "terraform-state-eks-platform"
    key     = "eks-platform/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "itera"
  }
}
