output security_group {
  value = "${aws_security_group.deployer.id}"
}

output secrets_bucket {
  value = "${aws_s3_bucket.secrets.bucket}"
}