package main

deny contains msg if {
    bucket := input.resource.aws_s3_bucket[name][_]
    project := object.get(bucket, ["tags", "Project"], "")
    project != "forensic-custody-api"
    msg := sprintf("S3 bucket '%s' must have tag Project = \"forensic-custody-api\"", [name])
}
