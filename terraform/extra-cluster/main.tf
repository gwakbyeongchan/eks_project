## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: MIT-0

# AWS 프로바이더 설정 (기본 리전)
provider "aws" {
  region = var.cluster_1_region
}

# AWS 프로바이더 설정 (ECR용)
provider "aws" {
  alias  = "ecr"
  region = var.cluster_1_region
}

# AWS 프로바이더 설정 (피어링용)
provider "aws" {
  alias  = "peer"
  region = var.cluster_2_region
}

# 현재 AWS 계정 정보 가져오기
data "aws_caller_identity" "current" {}

## ECR 설정
# ECR 복제 설정 (클러스터 2 리전으로 복제)
resource "aws_ecr_replication_configuration" "cross_ecr_replication" {
  replication_configuration {
    rule {
      destination {
        region      = var.cluster_2_region
        registry_id = data.aws_caller_identity.current.account_id
      }
    }
  }
}

# ECR 리포지토리 설정 (agones-openmatch-director)
resource "aws_ecr_repository" "agones-openmatch-director" {
  #checkov:skip=CKV_AWS_136:Encryption disabled for tests
  name                 = "agones-openmatch-director"
  image_tag_mutability = "MUTABLE" # 태그 변경 가능 여부 설정
  force_delete         = true # 비어 있지 않을 때도 삭제 가능 여부 설정
  image_scanning_configuration {
    scan_on_push = true # 이미지를 푸시할 때 스캔 활성화
  }
}

# ECR 리포지토리 설정 (supertuxkart-server)
resource "aws_ecr_repository" "supertuxkart-server" {
  #checkov:skip=CKV_AWS_136:Encryption disabled for tests
  name                 = "supertuxkart-server"
  image_tag_mutability = "IMMUTABLE" # 태그 변경 불가능 설정
  force_delete         = true # 비어 있지 않을 때도 삭제 가능 여부 설정
  image_scanning_configuration {
    scan_on_push = true # 이미지를 푸시할 때 스캔 활성화
  }
}

# ECR 리포지토리 설정 (agones-openmatch-mmf)
resource "aws_ecr_repository" "agones-openmatch-mmf" {
  #checkov:skip=CKV_AWS_136:Encryption disabled for tests
  name                 = "agones-openmatch-mmf"
  image_tag_mutability = "MUTABLE" # 태그 변경 가능 여부 설정
  force_delete         = true # 비어 있지 않을 때도 삭제 가능 여부 설정
  image_scanning_configuration {
    scan_on_push = true # 이미지를 푸시할 때 스캔 활성화
  }
}

# ECR 리포지토리 설정 (agones-openmatch-ncat-server)
resource "aws_ecr_repository" "agones-openmatch-ncat-server" {
  #checkov:skip=CKV_AWS_136:Encryption disabled for tests
  name                 = "agones-openmatch-ncat-server"
  image_tag_mutability = "MUTABLE" # 태그 변경 가능 여부 설정
  force_delete         = true # 비어 있지 않을 때도 삭제 가능 여부 설정
  image_scanning_configuration {
    scan_on_push = true # 이미지를 푸시할 때 스캔 활성화
  }
}

## 피어링 설정
# 요청자 측 VPC 피어링 연결 설정
resource "aws_vpc_peering_connection" "peer" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  peer_region = var.cluster_2_region
  auto_accept = false # 자동 수락 비활성화

  tags = {
    Side = "Requester" # 요청자 측 태그
  }
}

# 수락자 측 VPC 피어링 연결 설정
resource "aws_vpc_peering_connection_accepter" "peer" {
  provider                  = aws.peer
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
  auto_accept               = true # 자동 수락 활성화

  tags = {
    Side = "Accepter" # 수락자 측 태그
  }
}

# 요청자 측 경로 설정
resource "aws_route" "requester" {
  route_table_id            = var.requester_route
  destination_cidr_block    = var.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

# 수락자 측 경로 설정
resource "aws_route" "accepter" {
  provider                  = aws.peer
  route_table_id            = var.accepter_route
  destination_cidr_block    = var.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.peer.id
}

## AWS 글로벌 가속기 설정
# 프론트엔드용 글로벌 가속기 설정
resource "aws_globalaccelerator_accelerator" "aga_frontend" {
  #checkov:skip=CKV_AWS_75:Flow logs not needed
  name            = "${var.cluster_1_name}-om-fe"
  ip_address_type = "IPV4"
  enabled         = true # 가속기 활성화 여부
}

# 프론트엔드용 글로벌 가속기 리스너 설정
resource "aws_globalaccelerator_listener" "aga_frontend" {
  accelerator_arn = aws_globalaccelerator_accelerator.aga_frontend.id
  protocol        = "TCP"

  port_range {
    from_port = 50504
    to_port   = 50504
  }
}

# 프론트엔드용 글로벌 가속기 엔드포인트 그룹 설정
resource "aws_globalaccelerator_endpoint_group" "aga_frontend" {
  listener_arn = aws_globalaccelerator_listener.aga_frontend.id

  endpoint_configuration {
    endpoint_id                    = var.aws_lb_arn
    client_ip_preservation_enabled = false # 클라이언트 IP 보존 비활성화
    weight                         = 100 # 엔드포인트 가중치 설정
  }
}

## 게임 서버용 글로벌 가속기 설정 (클러스터 1)
resource "aws_globalaccelerator_custom_routing_accelerator" "aga_gs_cluster_1" {
  name            = "agones-openmatch-gameservers-cluster-1"
  ip_address_type = "IPV4"
  enabled         = true # 가속기 활성화 여부
}

# 게임 서버용 글로벌 가속기 리스너 설정 (클러스터 1)
resource "aws_globalaccelerator_custom_routing_listener" "aga_gs_cluster_1" {
  accelerator_arn = aws_globalaccelerator_custom_routing_accelerator.aga_gs_cluster_1.id
  port_range {
    from_port = 1
    to_port   = 65535
  }
}

# 게임 서버용 글로벌 가속기 엔드포인트 그룹 설정 (클러스터 1)
resource "aws_globalaccelerator_custom_routing_endpoint_group" "aga_gs_cluster_1" {
  listener_arn          = aws_globalaccelerator_custom_routing_listener.aga_gs_cluster_1.id
  endpoint_group_region = var.cluster_1_region
  destination_configuration {
    from_port = 7000
    to_port   = 7029
    protocols = ["TCP","UDP"]
  }

  endpoint_configuration {
    endpoint_id = var.cluster_1_gameservers_subnets[0]
  }
  endpoint_configuration {
    endpoint_id = var.cluster_1_gameservers_subnets[1]
  }
  # endpoint_configuration {
  #   endpoint_id = var.cluster_1_gameservers_subnets[2]
  # }
}

# 커스텀 라우팅 트래픽 허용 설정 (클러스터 1)
resource "null_resource" "allow_custom_routing_traffic_cluster_1" {
  triggers = {
    always_run         = "${timestamp()}"
    endpoint_group_arn = aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_1.id
    endpoint_id_1      = var.cluster_1_gameservers_subnets[0]
    endpoint_id_2      = var.cluster_1_gameservers_subnets[1]
    # endpoint_id_3      = var.cluster_1_gameservers_subnets[2]
  }

  provisioner "local-exec" {
    command = "aws globalaccelerator allow-custom-routing-traffic --endpoint-group-arn ${self.triggers.endpoint_group_arn} --endpoint-id ${self.triggers.endpoint_id_1} --allow-all-traffic-to-endpoint --region us-west-2 && aws globalaccelerator allow-custom-routing-traffic --endpoint-group-arn ${self.triggers.endpoint_group_arn} --endpoint-id ${self.triggers.endpoint_id_2} --allow-all-traffic-to-endpoint --region us-west-2"
  }
  depends_on = [
    aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_1
  ]
}

## 게임 서버용 글로벌 가속기 설정 (클러스터 2)
resource "aws_globalaccelerator_custom_routing_accelerator" "aga_gs_cluster_2" {
  name            = "agones-openmatch-gameservers-cluster-2"
  ip_address_type = "IPV4"
  enabled         = true # 가속기 활성화 여부
}

# 게임 서버용 글로벌 가속기 리스너 설정 (클러스터 2)
resource "aws_globalaccelerator_custom_routing_listener" "aga_gs_cluster_2" {
  accelerator_arn = aws_globalaccelerator_custom_routing_accelerator.aga_gs_cluster_2.id
  port_range {
    from_port = 1
    to_port   = 65535
  }
}

# 게임 서버용 글로벌 가속기 엔드포인트 그룹 설정 (클러스터 2)
resource "aws_globalaccelerator_custom_routing_endpoint_group" "aga_gs_cluster_2" {
  listener_arn          = aws_globalaccelerator_custom_routing_listener.aga_gs_cluster_2.id
  endpoint_group_region = var.cluster_2_region
  destination_configuration {
    from_port = 7000
    to_port   = 7029
    protocols = ["TCP","UDP"]
  }

  endpoint_configuration {
    endpoint_id = var.cluster_2_gameservers_subnets[0]
  }
  endpoint_configuration {
    endpoint_id = var.cluster_2_gameservers_subnets[1]
  }
  # endpoint_configuration {
  #   endpoint_id = var.cluster_2_gameservers_subnets[2]
  # }
}

# 커스텀 라우팅 트래픽 허용 설정 (클러스터 2)
resource "null_resource" "allow_custom_routing_traffic_cluster_2" {
  triggers = {
    always_run         = "${timestamp()}"
    endpoint_group_arn = aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_2.id
    endpoint_id_1      = var.cluster_2_gameservers_subnets[0]
    endpoint_id_2      = var.cluster_2_gameservers_subnets[1]
    # endpoint_id_3      = var.cluster_2_gameservers_subnets[2]
  }

  provisioner "local-exec" {
    command = "aws globalaccelerator allow-custom-routing-traffic --endpoint-group-arn ${self.triggers.endpoint_group_arn} --endpoint-id ${self.triggers.endpoint_id_1} --allow-all-traffic-to-endpoint --region us-west-2 && aws globalaccelerator allow-custom-routing-traffic --endpoint-group-arn ${self.triggers.endpoint_group_arn} --endpoint-id ${self.triggers.endpoint_id_2} --allow-all-traffic-to-endpoint --region us-west-2"
  }

  depends_on = [
    aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_2
  ]
}

# 매핑 설정 스크립트 실행 (클러스터 1)
resource "null_resource" "aga_mapping_cluster_1" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = "nohup ${path.cwd}/scripts/deploy-mapping-configmap.sh ${var.cluster_1_name} ${aws_globalaccelerator_custom_routing_accelerator.aga_gs_cluster_1.id} ${var.cluster_2_name} ${aws_globalaccelerator_custom_routing_accelerator.aga_gs_cluster_2.id}&"
  }

  depends_on = [
    aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_1,
    aws_globalaccelerator_custom_routing_endpoint_group.aga_gs_cluster_2
  ]
}

## Agones 다중 클러스터 할당 설정
resource "null_resource" "multicluster_allocation" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    when    = create
    command = "nohup ${path.cwd}/scripts/configure-multicluster-allocation.sh ${var.cluster_1_name} ${var.cluster_2_name} ${path.cwd}&"
  }
}
