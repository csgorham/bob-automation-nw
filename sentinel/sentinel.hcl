policy "require-tags" {
    source = "./require-tags.sentinel"
    enforcement_level = "hard-mandatory"
}

policy "restrict-instance-types" {
    source = "./restrict-instance-types.sentinel"
    enforcement_level = "soft-mandatory"
}

policy "enforce-s3-encryption" {
    source = "./enforce-s3-encryption.sentinel"
    enforcement_level = "hard-mandatory"
}