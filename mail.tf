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


resource "aws_s3_bucket" "landing_bucket" {
    bucket = "sotnich-learn-dataeng-landing"
    force_destroy = true
}

resource "aws_s3_bucket" "clean_bucket" {
    bucket = "sotnich-learn-dataeng-clean"
    force_destroy = true
}

resource "aws_s3_bucket" "athena_bucket" {
    bucket = "sotnich-learn-dataeng-athena"
    force_destroy = true
}

resource "aws_s3_bucket" "curated_bucket" {
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


resource "aws_iam_policy" "my_policy_03" {
    name = "LearnDataEngDMSLandingS3BucketPolicy"
    policy = file("${path.module}/Chapter06/DataEngDMSLandingS3BucketPolicy.json")
}

resource "aws_iam_role" "my_role_03" {
    name = "LearnDataEngDMSLandingS3BucketRole"
    assume_role_policy = file("${path.module}/Chapter06/DataEngDMSLandingS3BucketRole.json")
}

resource "aws_iam_role_policy_attachment" "my_policy_03_attachment" {
    role       = aws_iam_role.my_role_03.name
    policy_arn = aws_iam_policy.my_policy_03.arn
}

resource "aws_iam_role" "role_04" {
    name = "LearnDataEngDMSFirehoseS3Role"
    assume_role_policy = file("${path.module}/Chapter06/DataEngDMSFirehoseS3Role.json")
}

resource "aws_iam_role_policy_attachment" "my_policy_04_attachment" {
    role       = aws_iam_role.role_04.name
    policy_arn = aws_iam_policy.my_policy_03.arn
}


resource "aws_lambda_layer_version" "lambda_layer" {
    filename   = "${path.module}/Chapter03/awswrangler-layer-2.10.0-py3.8.zip"
    layer_name = "LearnTestAwsDataWrangler210_python38"

    compatible_runtimes = ["python3.8"]
}

data "archive_file" "lambda_zip_file_int" {
    type        = "zip"
    output_path = "/tmp/lambda_zip_file_int.zip"
    source {
        content  = file("Chapter03/CSVtoParquetLambda.py")
        filename = "CSVtoParquetLambda.py"
    }
}


resource "aws_lambda_function" "lambda_1" {
    function_name       = "LearnTestCSVtoParquetLambda"
    filename            = "${data.archive_file.lambda_zip_file_int.output_path}"
    source_code_hash    = "${data.archive_file.lambda_zip_file_int.output_base64sha256}"
    role                = aws_iam_role.my_role_01.arn
    runtime             = "python3.8"
    handler             = "CSVtoParquetLambda.lambda_handler"
    timeout             = 60
    layers              = [aws_lambda_layer_version.lambda_layer.arn]
}

resource "aws_lambda_permission" "allow_bucket" {
    statement_id  = "AllowExecutionFromS3Bucket"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.lambda_1.arn
    principal     = "s3.amazonaws.com"
    source_arn    = aws_s3_bucket.landing_bucket.arn
}

resource "aws_s3_bucket_notification" "lambda_1_trigger" {
    bucket = aws_s3_bucket.landing_bucket.id
    lambda_function {
        lambda_function_arn = aws_lambda_function.lambda_1.arn
        events              = ["s3:ObjectCreated:*"]
        filter_suffix       = ".csv"
    }
    depends_on = [aws_lambda_permission.allow_bucket]
}


resource "aws_db_instance" "mysql_db" {
    allocated_storage   = 20
    identifier          = "sotnich-test-dataeng-mysql-1"
    engine              = "mysql"
    instance_class      = "db.t3.micro"
    username            = "admin"
    password            = "admin123!"
    skip_final_snapshot = true
}

resource "aws_key_pair" "id_rsa" {
    key_name   = "deployer-key"
    public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "app_server" {
    ami                             = "ami-02b01316e6e3496d9"
    instance_type                   = "t2.micro"
    associate_public_ip_address     = true
    key_name                        = aws_key_pair.id_rsa.key_name
    user_data                       = <<EOF
#!/bin/bash
yum install -y mariadb
curl https://downloads.mysql.com/docs/sakila-db.zip -o sakila.zip
unzip sakila.zip
cd sakila-db
mysql --host=${aws_db_instance.mysql_db.address} --user=admin --password=${aws_db_instance.mysql_db.password} -f < sakila-schema.sql
mysql --host=${aws_db_instance.mysql_db.address} --user=admin --password=${aws_db_instance.mysql_db.password} -f < sakila-data.sql
EOF
}

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["dms.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "dms-access-for-endpoint" {
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  name               = "dms-access-for-endpoint"
}

resource "aws_iam_role_policy_attachment" "dms-access-for-endpoint-AmazonDMSRedshiftS3Role" {
    policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
    role       = aws_iam_role.dms-access-for-endpoint.name
}

resource "aws_iam_role" "dms-cloudwatch-logs-role" {
  assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
  name               = "dms-cloudwatch-logs-role"
}

resource "aws_iam_role_policy_attachment" "dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
  role       = aws_iam_role.dms-cloudwatch-logs-role.name
}

resource "aws_iam_role" "dms-vpc-role" {
    assume_role_policy = data.aws_iam_policy_document.dms_assume_role.json
    name               = "dms-vpc-role"
}

resource "aws_iam_role_policy_attachment" "dms-vpc-role-AmazonDMSVPCManagementRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  role       = aws_iam_role.dms-vpc-role.name
}

resource "aws_dms_replication_instance" "replication" {
    allocated_storage            = 10
    replication_instance_class   = "dms.t3.micro"
    replication_instance_id      = "mysql-s3-replication"
    multi_az                     = false
    publicly_accessible          = true

    vpc_security_group_ids = [
        "sg-09128aed3d4026e4e",
    ]

    depends_on = [
        aws_iam_role_policy_attachment.dms-access-for-endpoint-AmazonDMSRedshiftS3Role,
        aws_iam_role_policy_attachment.dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole,
        aws_iam_role_policy_attachment.dms-vpc-role-AmazonDMSVPCManagementRole,
        aws_iam_role.dms-vpc-role
    ]
}

resource "aws_dms_endpoint" "source" {
    endpoint_id                 = "${aws_db_instance.mysql_db.id}"
    endpoint_type               = "source"
    engine_name                 = "mysql"
    port                        = 3306
    database_name               = "sakila"
    password                    = "${aws_db_instance.mysql_db.password}"
    server_name                 = "${aws_db_instance.mysql_db.address}"
    ssl_mode                    = "none"
    username                    = "${aws_db_instance.mysql_db.username}"

    # need to wait until init script in the app server fills the sakila database
    depends_on = [aws_instance.app_server]
}

resource "aws_dms_endpoint" "target" {
    endpoint_id                 = "s3-landing-zone-sakilia-csv"
    endpoint_type               = "target"
    engine_name                 = "s3"
    ssl_mode                    = "none"
    
    s3_settings {
        bucket_name             = aws_s3_bucket.landing_bucket.id
        bucket_folder           = "sakila-db"
        add_column_name         = true
        service_access_role_arn = aws_iam_role.my_role_03.arn
        timestamp_column_name   = "tx_commit_time"
    }
}

resource "aws_dms_replication_task" "replication_task" {
    replication_task_id         = "dataeng-mysql-s3-sakila-task"
    replication_instance_arn    = aws_dms_replication_instance.replication.replication_instance_arn
    source_endpoint_arn         = aws_dms_endpoint.source.endpoint_arn
    target_endpoint_arn         = aws_dms_endpoint.target.endpoint_arn
    migration_type              = "full-load"
    start_replication_task      = true
    table_mappings              = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "599194392",
      "rule-name": "599153947",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include",
      "filters": []
    }
  ]
}
EOF

    # after the initial creation replication_task_settings will change
    # so we need ignore_changes to prevent update of this resource in case of the second run
    lifecycle {
        ignore_changes = [replication_task_settings]
        }
}

resource "aws_kinesis_firehose_delivery_stream" "s3_stream" {
    name        = "dataeng-firehose-streaming-s3"
    destination = "extended_s3"
    
    extended_s3_configuration {
        prefix                  = "streaming/!{timestamp:yyyy/MM/}"
        error_output_prefix     = "!{firehose:error-output-type}/!{timestamp:yyyy/MM/}"
        role_arn                = aws_iam_role.role_04.arn
        bucket_arn              = aws_s3_bucket.landing_bucket.arn
        buffer_interval         =  60
        buffer_size             = 1
    }
}

resource "aws_cloudformation_stack" "cognito" {
    name            = "Kinesis-Data-Generator-Cognito-User"
    template_url    = "https://aws-kdg-tools.s3.us-west-2.amazonaws.com/cognito-setup.json"
    parameters      = {"Username" = "admin", "Password" = "admin123"}
    capabilities    = ["CAPABILITY_IAM"]
}

resource "aws_glue_catalog_database" "streaming_db" {
    name = "streaming-db"
}

# resource "aws_glue_crawler" "example" {
#     database_name = aws_glue_catalog_database.streaming_db.name
#     name          = "learn-dataeng-streaming-crawler"
#     role          = aws_iam_role.my_role_02.arn

#     s3_target {
#         path = "s3://${aws_s3_bucket.landing_bucket.bucket}/streaming"
#     }
# }


output "app_server_name" {
    value = aws_instance.app_server.public_dns
}

output "db_address" {
    value = aws_db_instance.mysql_db.address
}