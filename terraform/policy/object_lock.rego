package main

deny contains msg if {
    bucket := input.resource.aws_s3_bucket[name][_]
    bucket.object_lock_enabled != true
    msg := sprintf("S3 bucket '%s' must have Object Lock enabled (chain-of-custody requirement)", [name])
}
