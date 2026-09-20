package main

deny contains msg if {
    role := input.resource.aws_iam_role[name][_]
    not startswith(role.name, "forensic-custody-api-")
    msg := sprintf("IAM role '%s' must have a name that starts with 'forensic-custody-api-'", [name])
}
