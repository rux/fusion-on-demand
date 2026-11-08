import os
import hmac
import boto3

ec2 = boto3.client("ec2")

def lambda_handler(event, context):
    token = (event.get("queryStringParameters") or {}).get("token", "")

    if not hmac.compare_digest(token, os.environ["WAKE_TOKEN"]):
        return {"statusCode": 403, "body": "Forbidden"}

    response = ec2.describe_instances(
        Filters=[{"Name": "tag:Name", "Values": ["fusion"]}]
    )

    instances = [
        instance
        for reservation in response["Reservations"]
        for instance in reservation["Instances"]
        if instance["State"]["Name"] != "terminated"
    ]

    if len(instances) != 1:
        raise RuntimeError(f"Expected one Fusion instance, found {len(instances)}")

    instance_id = instances[0]["InstanceId"]
    state = instances[0]["State"]["Name"]

    if state == "stopped":
        ec2.start_instances(InstanceIds=[instance_id])
        message = "Fusion is starting!"
    elif state in ("running", "pending"):
        message = "Fusion is already running or starting."
    else:
        message = f"EC2 is currently {state}."

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": f'<h2>{message}</h2><p><a href="{os.environ["FUSION_URL"]}">Open Fusion</a></p>'
    }
