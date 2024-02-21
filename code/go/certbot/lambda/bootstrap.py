import base64
import hashlib
import json
import boto3

# Initialize a boto3 client
s3 = boto3.client("s3")


def base64url_encode(input):
    return base64.urlsafe_b64encode(input).rstrip(b"=")


def lambda_handler(event, context):
    # Specify your bucket name and object key
    bucket_name = "apinant-letsencrypt"
    object_key = "jwk.json"
    path = event["path"]
    token = path.split("/")[-1]

    # Fetch the JWK from S3
    response = s3.get_object(Bucket=bucket_name, Key=object_key)
    jwk_content = response["Body"].read().decode("utf-8")
    jwk = json.loads(jwk_content)

    # Extract modulus and exponent from the JWK
    modulus_base64 = jwk["n"]
    exponent_base64 = jwk["e"]

    modulus = base64.urlsafe_b64decode(modulus_base64 + "==")
    exponent = base64.urlsafe_b64decode(exponent_base64 + "==")

    # Construct the JWK for thumbprint calculation
    jwk_for_thumbprint = json.dumps(
        {
            "e": base64url_encode(exponent).decode("utf-8"),
            "kty": "RSA",
            "n": base64url_encode(modulus).decode("utf-8"),
        },
        separators=(",", ":"),
    )

    thumbprint = hashlib.sha256(jwk_for_thumbprint.encode("utf-8")).digest()
    thumbprint_encoded = base64url_encode(thumbprint).decode("utf-8")

    return {
        "statusCode": 200,
        "statusDescription": "200 OK",
        "isBase64Encoded": False,
        "headers": {"Content-Type": "text/plain"},
        "body": token + "." + thumbprint_encoded,
    }
