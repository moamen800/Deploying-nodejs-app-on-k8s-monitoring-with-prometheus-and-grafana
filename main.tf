provider "aws" {
  region = "eu-north-1"
}

resource "aws_instance" "k8s" {
  count             = 3
  ami               = "ami-0399a684c97d981a2"
  instance_type     = "t3.medium"             
  key_name          = "keypair"
  availability_zone = "eu-north-1a"
  subnet_id         = "subnet-0bf8d75f3412e4b24" 
  vpc_security_group_ids = ["sg-0286bed22021f1936"]

  root_block_device {
    volume_size = lookup(
      {
        0 = 20  # Master node storage: 20 GB
        1 = 10  # Worker node 1 storage: 10 GB
        2 = 10  # Worker node 2 storage: 10 GB
      },
      count.index,
      10
    )
    volume_type = "gp2" # General-purpose SSD
  }

  # Assign a specific script for each instance
  user_data = filebase64(
    lookup(
      {
        0 = "${path.module}/scripts/install-k8s-Master.sh"
        1 = "${path.module}/scripts/install-k8s-Node1.sh"
        2 = "${path.module}/scripts/install-k8s-Node2.sh"
      },
      count.index,
      ""
    )
  )

  tags = {
    Name = lookup(
      {
        0 = "master"
        1 = "node1"
        2 = "node2"
      },
      count.index,
      "unknown"
    )
  }
}
