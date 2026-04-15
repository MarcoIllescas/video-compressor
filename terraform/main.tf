provider "aws" {
    access_key = "test"
    secret_key = "test"
    region     = "us-east-1"

    # Localstack configuration
    s3_use_path_style = true
    skip_credentials_validation = true
    skip_metadata_api_check = true
    skip_requesting_account_id = true

    endpoints {
        s3              = "http://localhost:4566"
        dynamodb        = "http://localhost:4566"
        lambda          = "http://localhost:4566"
        stepfunctions   = "http://localhost:4566"
        iam             = "http://localhost:4566"
        events          = "http://localhost:4566"
    }
}

# ------------------------------------------------------ #
#                        S3 Buckets                      #
# ------------------------------------------------------ #
resource "aws_s3_bucket" "input_videos_1080p" {
    bucket = "video-compressor-1080p"
}

resource "aws_s3_bucket" "output_videos_720p" {
    bucket = "video-compressor-720p"
}

resource "aws_s3_bucket" "output_videos_480p" {
    bucket = "video-compressor-480p"
}


# ------------------------------------------------------ #
#                         DynamoDB                       #
# ------------------------------------------------------ #
resource "aws_dynamodb_table" "video_metadata" {
    name           = "video_metadata"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "video_id"

    attribute {
        name = "video_id"
        type = "S"
    }
}


# ------------------------------------------------------ #
#                         IAM Roles                      #
# ------------------------------------------------------ #

#             Lambda role for 720p processing            #
resource "aws_iam_role" "lambda_role_720p" {
    name                = "lambda-role-720p"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_lambda_720p" {
    name   = "lambda-policy-720p"
    role   = aws_iam_role.lambda_role_720p.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.input_videos_1080p.arn}/*"
            },
            {
                Action = ["s3:PutObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.output_videos_720p.arn}/*"
            },
        ]
    })
}

#             Lambda role for 480p processing            #
resource "aws_iam_role" "lambda_role_480p" {
    name                = "lambda-role-480p"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_lambda_480p" {
    name   = "lambda-policy-480p"
    role   = aws_iam_role.lambda_role_480p.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.output_videos_720p.arn}/*"
            },
            {
                Action = ["s3:PutObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.output_videos_480p.arn}/*"
            },
        ]
    })
}

#                      Metadata role                     #
resource "aws_iam_role" "metadata_role" {
    name                = "metadata-role"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_metadata" {
    name   = "metadata-policy"
    role   = aws_iam_role.metadata_role.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject", "s3:HeadObject"]
                Effect = "Allow"
                Resource = [
                    "${aws_s3_bucket.input_videos_1080p.arn}/*",
                    "${aws_s3_bucket.output_videos_720p.arn}/*",
                    "${aws_s3_bucket.output_videos_480p.arn}/*"
                ]
            },
            {
                Action = ["dynamodb:PutItem"]
                Effect = "Allow"
                Resource = "${aws_dynamodb_table.video_metadata.arn}"
            },
        ]
    })
}