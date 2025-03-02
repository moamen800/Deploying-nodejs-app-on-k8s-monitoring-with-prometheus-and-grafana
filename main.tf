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
  # iam_instance_profile = aws_iam_instance_profile.k8s_ebs_efs_instance_profile.name

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




# # -------------------------------
# # IAM Role for EC2 Instances (EBS & EFS CSI Drivers)
# # -------------------------------
# resource "aws_iam_role" "k8s_ebs_efs_role" {
#   name = "k8s-ebs-efs-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Principal = {
#         Service = "ec2.amazonaws.com"
#       },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }

# # Custom IAM Policy for EFS CSI Driver
# resource "aws_iam_policy" "efs_csi_policy" {
#   name        = "AmazonEFSCSIDriverPolicy"
#   description = "Permissions for the Amazon EFS CSI driver"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect   = "Allow",
#         Action   = [
#           "elasticfilesystem:DescribeAccessPoints",
#           "elasticfilesystem:DescribeFileSystems",
#           "elasticfilesystem:DescribeMountTargets",
#           "ec2:DescribeAvailabilityZones"
#         ],
#         Resource = "*"
#       },
#       {
#         Effect   = "Allow",
#         Action   = ["elasticfilesystem:CreateAccessPoint"],
#         Resource = "*",
#         Condition = {
#           "StringLike" = {
#             "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       },
#       {
#         Effect   = "Allow",
#         Action   = ["elasticfilesystem:TagResource"],
#         Resource = "*",
#         Condition = {
#           "StringLike" = {
#             "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       },
#       {
#         Effect   = "Allow",
#         Action   = "elasticfilesystem:DeleteAccessPoint",
#         Resource = "*",
#         Condition = {
#           "StringEquals" = {
#             "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
#           }
#         }
#       }
#     ]
#   })
# }

# # Attach AWS Managed Policy for EBS CSI Driver
# resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
#   role       = aws_iam_role.k8s_ebs_efs_role.name
# }

# # Attach EFS CSI Policy to the IAM Role
# resource "aws_iam_role_policy_attachment" "efs_csi_policy_attachment" {
#   policy_arn = aws_iam_policy.efs_csi_policy.arn
#   role       = aws_iam_role.k8s_ebs_efs_role.name
# }

# # IAM Instance Profile for EC2 Instances
# resource "aws_iam_instance_profile" "k8s_ebs_efs_instance_profile" {
#   name = "k8s-ebs-efs-instance-profile"
#   role = aws_iam_role.k8s_ebs_efs_role.name
# }






# # ------------------------------------------
# # IAM Role for EC2 Instances (Administrator Access)
# # ------------------------------------------
# resource "aws_iam_role" "k8s_admin_role" {
#   name = "k8s-admin-role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [{
#       Effect = "Allow",
#       Principal = {
#         Service = "ec2.amazonaws.com"
#       },
#       Action = "sts:AssumeRole"
#     }]
#   })
# }

# # ------------------------------------------
# # Attach Administrator Access Policy to IAM Role
# # ------------------------------------------
# resource "aws_iam_role_policy_attachment" "k8s_admin_attachment" {
#   policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
#   role       = aws_iam_role.k8s_admin_role.name
# }

# # ------------------------------------------
# # IAM Instance Profile for EC2 Instances
# # ------------------------------------------
# resource "aws_iam_instance_profile" "k8s_instance_profile" {
#   name = "k8s-instance-profile"
#   role = aws_iam_role.k8s_admin_role.name
# }



