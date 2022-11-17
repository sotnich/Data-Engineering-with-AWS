terraform {
    required_providers {
        aws = {
            source  = "hashicorp/aws"
            version = "~> 4.0"
        }
    }
}

provider "aws" {
    region = "eu-west-3"
}

resource "aws_s3_bucket" "b1" {
    bucket = "sotnich-learn-dataeng-landing"
    force_destroy = true
}

resource "aws_s3_bucket" "b2" {
    bucket = "sotnich-learn-dataeng-clean"
    force_destroy = true
}

resource "aws_s3_bucket" "b3" {
    bucket = "sotnich-learn-dataeng-athena"
    force_destroy = true
}

resource "aws_s3_bucket" "landing" {
    bucket = "sotnich-learn-dataeng-curated"
    force_destroy = true
}

resource "aws_iam_policy" "my_policy_01" {
    name = "LearnDataEngLambdaS3CWGluePolicy"
    policy = file("${path.module}/Chapter03/DataEngLambdaS3CWGluePolicy.json")
}

resource "aws_iam_role" "my_role_01" {
    name = "LearnDataEngLambdaS3CWGlueRole"
    assume_role_policy = file("${path.module}/Chapter03/DataEngLambdaS3CWGlueRole.json")
}

resource "aws_iam_role_policy_attachment" "my_policy_01_attachment" {
    role       = aws_iam_role.my_role_01.name
    policy_arn = aws_iam_policy.my_policy_01.arn
}


resource "aws_iam_policy" "my_policy_02" {
    name = "LearnDataEngGlueCWS3CuratedZoneWrite"
    policy = file("${path.module}/Chapter07/DataEngGlueCWS3CuratedZoneWrite.json")
}

resource "aws_iam_role" "my_role_02" {
    name = "LearnDataEngGlueCWS3CuratedZoneRole"
    assume_role_policy = file("${path.module}/Chapter07/DataEngGlueCWS3CuratedZoneRole.json")
}

resource "aws_iam_role_policy_attachment" "my_policy_02_attachment_01" {
    role       = aws_iam_role.my_role_02.name
    policy_arn = aws_iam_policy.my_policy_02.arn
}

resource "aws_iam_role_policy_attachment" "my_policy_02_attachment_02" {
    role       = aws_iam_role.my_role_02.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_lambda_layer_version" "lambda_layer" {
    filename   = "awswrangler-layer-2.10.0-py3.8.zip"
    layer_name = "LearnTestAwsDataWrangler210_python38"

    compatible_runtimes = ["python3.8"]
}

# data "archive_file" "lambda_zip_file_int" {
#     type        = "zip"
#     output_path = "/tmp/lambda_zip_file_int.zip"
#     source {
#         content  = file("Chapter03/CSVtoParquetLambda.py")
#         filename = "CSVtoParquetLambda.py"
#     }
# }

# resource "aws_lambda_function" "test_lambda" {
#     function_name = "LearnTestCSVtoParquetLambda"
#     filename         = "${data.archive_file.lambda_zip_file_int.output_path}"
#     source_code_hash = "${data.archive_file.lambda_zip_file_int.output_base64sha256}"
#     role          = aws_iam_role.my_role_01.arn
#     runtime       = "python3.8"
#     handler       = "lambda_handler"
# }
