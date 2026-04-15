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
                Resource = "${aws_s3_bucket.input_videos_1080p.arn}/*"
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

# ------------------------------------------------------ #
#                 Packing Lambda functions               #
# ------------------------------------------------------ #
data "archive_file" "zip_lambda_720p" {
    type        = "zip"
    source_dir  = "../src/lambda_720p"
    output_path = "lambda_720p.zip"
}

data "archive_file" "zip_lambda_480p" {
    type        = "zip"
    source_dir  = "../src/lambda_480p"
    output_path = "lambda_480p.zip"
}

data "archive_file" "zip_lambda_metadata" {
    type        = "zip"
    source_dir  = "../src/lambda_metadata"
    output_path = "lambda_metadata.zip"
}

# ------------------------------------------------------ #
#                 Creating Lambda functions              #
# ------------------------------------------------------ #
resource "aws_lambda_function" "lambda_720p" {
    filename         = data.archive_file.zip_lambda_720p.output_path
    source_code_hash = data.archive_file.zip_lambda_720p.output_base64sha256
    function_name    = "video-convert-720p"
    role             = aws_iam_role.lambda_role_720p.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 60
    memory_size      = 512

    environment {
        variables = {
            BUCKET_OUT       = aws_s3_bucket.output_videos_720p.bucket
            RESOLUTION       = "1280x720"
            AWS_ENDPOINT_URL = "http://localhost:4566"
        }
    }
}

resource "aws_lambda_function" "lambda_480p" {
    filename         = data.archive_file.zip_lambda_480p.output_path
    source_code_hash = data.archive_file.zip_lambda_480p.output_base64sha256
    function_name    = "video-convert-480p"
    role             = aws_iam_role.lambda_role_480p.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 60
    memory_size      = 512

    environment {
        variables = {
            BUCKET_OUT       = aws_s3_bucket.output_videos_480p.bucket
            RESOLUTION       = "854x480"
            AWS_ENDPOINT_URL = "http://localhost:4566"
        }
    }
}

resource "aws_lambda_function" "lambda_metadata" {
    filename         = data.archive_file.zip_lambda_metadata.output_path
    source_code_hash = data.archive_file.zip_lambda_metadata.output_base64sha256
    function_name    = "save-video-metadata"
    role             = aws_iam_role.metadata_role.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 10
    memory_size      = 128

    environment {
        variables = {
            AWS_ENDPOINT_URL = "http://localhost:4566"
        }
    }
}