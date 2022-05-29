provider "aws" {
  region = "ap-south-1"
  profile = "task6-profile"
}
resource "aws_db_instance" "myrdsdb" {
  allocated_storage    = 10
  identifier           = "dbinstance"
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = "rdswordpressdb"
  username             = "Vamsi"
  password             = "vamsi1234"
  parameter_group_name = "default.mysql5.7"
  publicly_accessible = true
  skip_final_snapshot  = true
  iam_database_authentication_enabled = true
  
  tags = {
    Name = "wordpressdatabase"
  }
}

provider "kubernetes" {
  config_context = "minikube"
}

resource "kubernetes_deployment" "Wordpress-deploy" {
  metadata{
    name= "wordpress"
    labels ={
      app = "wordpress"
      env = "task-env"
    }
  }
   spec {
    replicas = 1
    selector {
      match_labels = {
        app = "wordpress"
        env = "task-env"
      }
    }
    

    template {
      metadata {
        labels = {
          app = "wordpress"
          env = "task-env"
        }
      }

      spec {
        container{
          name = "mywordpress"
          image = "wordpress"
          
          env{
            name = "WORDPRESS_DB_HOST"
            value = aws_db_instance.myrdsdb.address
          }
          env{
            name = "WORDPRESS_DB_USER"
            value = aws_db_instance.myrdsdb.username
          }
          env{
            name = "WORDPRESS_DB_PASSWORD"
            value = aws_db_instance.myrdsdb.password
          }
          env{
          name = "WORDPRESS_DB_NAME"
          value = aws_db_instance.myrdsdb.name
          }
        }
      }
    }
   }

}


resource "kubernetes_service" "wp-expose" {

  metadata {
    name = "public-wordpress"
  }
  
  spec {
    selector = {
      app = kubernetes_deployment.Wordpress-deploy.spec.0.template.0.metadata[0].labels.app
    }
    port {
      node_port   = 30080 
      port        = 80
      target_port = 80
    }
    type = "NodePort"
}
depends_on = [kubernetes_deployment.Wordpress-deploy]

}

output "database-address" {
    value = "${aws_db_instance.myrdsdb.address}"
    
    depends_on=[aws_db_instance.myrdsdb]
}

/*resource "null_resource" "open-site"{
depends_on =[kubernetes_service.wp-expose]

provisioner "local-exec" {
command = "firefox http://192.168.99.103:30080"
}


}*/
/*resource "null_resource" "kube-cmds" {
  provisioner "local-exec" {
    command = "minikube service list"
    
  }
  depends_on = [
      kubernetes_deployment.abhiwp,
      kubernetes_service.abhiwplb,
      aws_db_instance.abhidatabase
 
     ]
}*/