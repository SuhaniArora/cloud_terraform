provider "aws" {
  profile = "suhani"
  region  = "ap-south-1"
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_instance" "web" {
  ami             = "ami-0447a12f28fddb066"
  instance_type   = "t2.micro"
  key_name        = "redhat1_key"
  security_groups = ["launch-wizard-3"]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Suhani/Desktop/aws/redhat1_key.pem")
    host     = aws_instance.web.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

  tags = {
    Name = "redhat_webserver_terr"
  }
}

resource "aws_ebs_volume" "web_vol" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1

  tags = {
    Name = "webserver_vol"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.web_vol.id
  instance_id = aws_instance.web.id
  force_detach= true  
}

resource "null_resource" "ip_file"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.web.public_ip} > publicip.txt"
  	}
}

resource "null_resource" "git_code"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Suhani/Desktop/aws/redhat1_key.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/SuhaniArora/cloud_terraform.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "b" {
  bucket = "webserver-bucket-terr"
  acl    = "public-read"
  region = "ap-south-1"
  force_destroy = true
  tags = {
    Name        = "web_bucket"
    Environment = "Dev"
  } 
}


resource "aws_s3_bucket_object" "s3_object" {
  depends_on = [
    aws_s3_bucket.b,
  ]
  bucket = aws_s3_bucket.b.id
  key    = "image1"
  acl    = "public-read"
  source = "C:/Users/Suhani/Desktop/aws/img1_s3.png"
  etag   = filemd5("C:/Users/Suhani/Desktop/aws/img1_s3.png")
}

resource "null_resource" "url_file"  {
  provisioner "local-exec" {
    command = "echo  ${aws_s3_bucket.b.bucket_regional_domain_name}/${aws_s3_bucket_object.s3_object.id} > s3_url.txt"
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "webserver_cloud_front"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "S3-webserver-bucket-terr"
    //origin_path = "image1"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "image1"
 
  //aliases = ["mysite.example.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-webserver-bucket-terr"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/Suhani/Desktop/aws/redhat1_key.pem")
    host     = aws_instance.web.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod +x /tmp/script.sh",
      "sudo su << EOF" ,
      "echo \"<img src='http://${self.domain_name}/$aws_s3_bucket_object.s3_object.key}' height='200px' width='200px'>\" >> /var/www/html/index.php",
      "EOF" 
    ]
  }  
}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.b.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.b.id
  policy = data.aws_iam_policy_document.s3_policy.json
}
