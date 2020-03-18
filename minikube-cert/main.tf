# Define o provedor AWS onde serão criados os recursos
provider "aws" {
  region = var.aws_region
}

# Cria um VPC que receberá as instâncias e recursos
resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}
# Cria um Internet Gateway que possibilita a comunicação do VPN com o mundo externo
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}
# Cria a Regra que permite acesso a Internet de/para o VPC
resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}
# Cria uma subrede no VPC que ira receber as instâncias
resource "aws_subnet" "default" {
  vpc_id                  = aws_vpc.default.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Cria um "security group" para o EC2 visando permitir o acesso Web
resource "aws_security_group" "default" {
  name        = "fiap-ec2-security-group-ec2-instance"
  description = "Grupo de seguranca do EC2"
  vpc_id      = aws_vpc.default.id

  # Acesso TOTAL de qualquer um
  ingress {
    from_port   = 0
    to_port     = 65353
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Acesso de saida para internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Para verificar o resultado do script: cat /var/log/cloud-init-output.log
data "template_file" "init" {
  template = file("${path.module}/../preparar.sh")
}

resource "aws_instance" "minikube" {
  
  # Define o script de inicialização do EC2:
  user_data = data.template_file.init.rendered
  
  # Define a chave
  key_name  = var.key_name
  
  # Define o nome da VM
  tags = {
    Name = "fiap vm : minikube"
  }  
  
  # Define tipo da VM (CPU e Memoria)
  instance_type = var.instance_type

  # Criar um disco com 30 GB
  root_block_device {
    volume_size = 30
  }
  
  # Versão do Sistema Operacional (Ubuntu)
  ami = lookup(var.aws_amis, var.aws_region)

  # Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = aws_subnet.default.id
}

# ELB com certificado para HTTPS

# Cria um "security group" para o ELB para permitir o acesso Web
resource "aws_security_group" "elb" {
  name        = "fiap-elb-security-group-minikube"
  description = "Grupo de seguranca do ELB"
  vpc_id      = "${aws_vpc.default.id}"
  # Acesso de qualquer um
  ingress {
    from_port   = 0
    to_port     = 65353
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Acesso de saida para internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
  
# Cria um Elastic Load Balancer fazer o balanceamento nas instâncias EC2
# Regra do Load Balancer: acesso a porta 80
resource "aws_elb" "elb" {
  name = "fiap-elb-minikube"
  subnets         = ["${aws_subnet.default.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${aws_instance.minikube.id}"]
  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }
}

# Uso futuro: outros discos na instancia
/*
# Criar um disco Extra com 35 GB
resource "aws_ebs_volume" "vol1" {
    size = 35
    type = "gp2"
    availability_zone = "${aws_instance.web.availability_zone}"
}
resource "aws_volume_attachment" "vol1" {
    instance_id = "${aws_instance.web.id}"
    volume_id = "${aws_ebs_volume.vol1.id}"
    device_name = "/dev/xvdb"
}
# Define um par de chaves a partir da key publica
resource "aws_key_pair" "auth" {
  key_name   = var.key_name
  # executar o comando em sua maquina local: ssh-keygen -y -f ./chave-fiap.pem > public_key.pem
  # pegar o conteudo do arquivo e inserir no public_key.pem.
  # public_key = file(var.public_key_path)
}
*/